//
//  DemoDayBackup.swift
//  glucose
//
//  DEBUG 전용: 데모 계정에 있는 "실제 기록 날"(예: 실제 사용자 하루)을 시나리오가 건드리지 않게 지키고,
//  필요할 때 그대로 다시 넣는다.
//  - 백업: 그날 음식·인슐린 기록(+ 음식 사진 파일)을 Mac의 ~/glubee-demo-backup/<날짜>.json 에 저장한다.
//    실제 건강 기록이라 **저장소에 넣지 않는다**(시뮬레이터에서만 Mac 폴더를 쓴다. 실기기는 앱 문서 폴더).
//  - 보호: 백업이 있는 날은 DemoScenarioSeed가 지우지도, 시나리오 기록을 넣지도 않는다.
//  - 복원: 백업한 기록 중 서버에 없는 것만 다시 넣는다(같은 시각·내용이면 건너뜀). 그래프 값은 지우지 않으므로 그대로다.
//

#if DEBUG
import Foundation

@MainActor
enum DemoDayBackup {

    struct Backup: Codable {
        var day: String
        var savedAt: Date
        var intakes: [Intake]
        var insulin: [Insulin]

        struct Intake: Codable {
            var occurredAt: Date
            var context: String
            var photoId: UUID?
            var items: [Item]
        }

        struct Item: Codable {
            var name: String
            var count: Int?
            var unit: String?
            var categoryHint: String?
            var tags: [String]
        }

        struct Insulin: Codable {
            var occurredAt: Date
            var units: Double
            var kind: String
        }
    }

    // MARK: - 폴더

    /// 시뮬레이터: Mac의 ~/glubee-demo-backup (Desktop 아래는 권한 창 때문에 쓰지 않는다). 실기기: 앱 문서 폴더
    static var directory: URL {
        if let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] {
            return URL(fileURLWithPath: home).appendingPathComponent("glubee-demo-backup", isDirectory: true)
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("glubee-demo-backup", isDirectory: true)
    }

    private static func file(_ day: String) -> URL { directory.appendingPathComponent("\(day).json") }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// 백업이 있는(= 시나리오가 건드리면 안 되는) 날짜들 "yyyy-MM-dd"
    static var protectedDays: Set<String> {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return Set(files.filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent })
    }

    static func load(_ day: String) -> Backup? {
        guard let data = try? Data(contentsOf: file(day)) else { return nil }
        return try? decoder.decode(Backup.self, from: data)
    }

    // MARK: - 백업

    /// 그날 기록을 서버에서 읽어 저장한다. 결과 문장(값·사진 주소는 담지 않는다)
    static func backup(day: Date) async -> String {
        let dayString = ReportDay.apiString(from: day)
        let items = await records(on: dayString)
        guard let items else { return "기록을 불러오지 못했어요. 로그인 상태를 확인해 주세요." }
        var backup = Backup(day: dayString, savedAt: .now, intakes: [], insulin: [])
        for item in items {
            switch item {
            case .intake(let record):
                backup.intakes.append(.init(
                    occurredAt: record.occurredAt, context: record.context.rawValue, photoId: record.photoId,
                    items: record.items.map { .init(name: $0.name, count: $0.count, unit: $0.unit,
                                                    categoryHint: $0.categoryHint, tags: $0.tags) }))
            case .insulin(let record):
                backup.insulin.append(.init(occurredAt: record.occurredAt, units: record.units, kind: record.kind))
            }
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(backup).write(to: file(dayString), options: .atomic)
        } catch {
            return "백업 파일을 쓰지 못했어요."
        }
        // 음식 사진 파일도 함께(나중에 사진이 사라져도 다시 올릴 수 있게)
        var photos = 0
        for photoId in backup.intakes.compactMap(\.photoId) {
            let target = directory.appendingPathComponent("\(dayString)-\(photoId.uuidString).jpg")
            if FileManager.default.fileExists(atPath: target.path) { photos += 1; continue }
            guard let url = await PhotoViewURLCache.shared.url(for: photoId),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  (try? data.write(to: target, options: .atomic)) != nil else { continue }
            photos += 1
        }
        return "\(dayString) 백업: 음식 \(backup.intakes.count)건(사진 \(photos)장), 인슐린 \(backup.insulin.count)건. 이 날은 시나리오가 건드리지 않아요."
    }

    // MARK: - 복원

    /// 백업이 있는 모든 날을 복원한다(서버에 이미 있는 기록은 건너뜀)
    static func restoreAll() async -> String {
        var lines: [String] = []
        for day in protectedDays.sorted() {
            lines.append(await restore(day: day))
        }
        return lines.isEmpty ? "백업한 날이 없어요." : lines.joined(separator: "\n")
    }

    static func restore(day: String) async -> String {
        guard let backup = load(day) else { return "\(day) 백업이 없어요." }
        guard let existing = await records(on: day) else { return "\(day) 기록을 불러오지 못해 복원하지 않았어요." }
        var created = 0, skipped = 0, failed = 0
        for intake in backup.intakes {
            let names = intake.items.map(\.name)
            let already = existing.contains { item in
                if case .intake(let record) = item {
                    return abs(record.occurredAt.timeIntervalSince(intake.occurredAt)) < 60 && record.items.map(\.name) == names
                }
                return false
            }
            if already { skipped += 1; continue }
            if await create(intake, photoId: intake.photoId) {
                created += 1
            } else if let photoId = await reupload(intake, day: day), await create(intake, photoId: photoId) {
                created += 1
            } else {
                failed += 1
            }
        }
        for dose in backup.insulin {
            let already = existing.contains { item in
                if case .insulin(let record) = item {
                    return abs(record.occurredAt.timeIntervalSince(dose.occurredAt)) < 60
                        && record.units == dose.units && record.kind == dose.kind
                }
                return false
            }
            if already { skipped += 1; continue }
            let request = InsulinEventRequest(occurredAt: dose.occurredAt, units: dose.units, kind: dose.kind)
            if (try? await APIClient.shared.send(path: "/v1/insulin-events", method: .post, body: request) as InsulinEventResponse) != nil {
                created += 1
            } else {
                failed += 1
            }
        }
        return "\(day) 복원: 새로 \(created)건, 이미 있음 \(skipped)건" + (failed > 0 ? ", 실패 \(failed)건" : "")
    }

    private static func create(_ intake: Backup.Intake, photoId: UUID?) async -> Bool {
        let request = CreateIntakeRequest(
            context: intake.context, occurredAt: intake.occurredAt, photoId: photoId,
            items: intake.items.map { IntakeItemRequest(name: $0.name, count: $0.count, unit: $0.unit,
                                                        categoryHint: $0.categoryHint, tags: $0.tags) })
        return (try? await APIClient.shared.send(path: "/v1/intakes", method: .post, body: request) as IntakeResponse) != nil
    }

    /// 예전 사진을 쓸 수 없을 때 백업해 둔 사진 파일을 새로 올린다
    private static func reupload(_ intake: Backup.Intake, day: String) async -> UUID? {
        guard let photoId = intake.photoId, let context = IntakeContext(rawValue: intake.context),
              let data = try? Data(contentsOf: directory.appendingPathComponent("\(day)-\(photoId.uuidString).jpg"))
        else { return nil }
        return try? await PhotoUploader().upload(imageData: data, context: context)
    }

    // MARK: - 읽기

    /// 그날("yyyy-MM-dd") 음식·인슐린 기록 전체. 불러오지 못하면 nil
    private static func records(on day: String) async -> [RecordItem]? {
        let repository = LiveRecordRepository()
        var result: [RecordItem] = []
        for kind in 0..<2 {
            var cursor: String?
            repeat {
                let page = try? await (kind == 0
                    ? repository.fetchIntakePage(cursor: cursor, limit: 100)
                    : repository.fetchInsulinPage(cursor: cursor, limit: 100))
                guard let page else { return nil }
                result += page.items.filter { ReportDay.apiString(from: $0.occurredAt) == day }
                // 최신순이라 그날보다 이전으로 넘어가면 멈춘다
                if let last = page.items.last, ReportDay.apiString(from: last.occurredAt) < day { break }
                cursor = page.nextCursor
            } while cursor != nil
        }
        return result
    }
}
#endif
