#if DEBUG
import UIKit

/// 화면 검증 전용. API/기존 저장소를 읽거나 쓰지 않고 앱 재실행 시 원래 예시로 돌아온다.
@MainActor
final class TimelineSamples: RecordRepository, IntakeServing, InsulinServing {
    static var isEnabled: Bool {
        LocalDemoSession.shared.isActive || ProcessInfo.processInfo.arguments.contains("-timelineSample")
        || ProcessInfo.processInfo.arguments.contains("-timelineEmptySample")
    }
    private static let commandLineSamples = TimelineSamples()
    static var shared: TimelineSamples {
        LocalDemoSession.shared.isActive ? LocalDemoSession.shared.samples : commandLineSamples
    }
    let photos: PendingPhotoStore
    let dayClose: DayCloseStore
    let preferences: UserPreferences
    private var intakes: [UUID: IntakeResponse] = [:]
    private var insulins: [UUID: InsulinEventResponse] = [:]

    init() {
        let defaults = UserDefaults(suiteName: "timeline-preview-\(UUID())")!
        dayClose = DayCloseStore(defaults: defaults)
        preferences = UserPreferences(defaults: defaults)
        photos = PendingPhotoStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("timeline-\(UUID())"),
                                   isAuthenticated: { false }, onActivity: { _ in })
        guard !ProcessInfo.processInfo.arguments.contains("-timelineEmptySample") else { return }
        let day = ReportDay.today()
        for record in ReportSamples.records(day) {
            intakes[record.id] = Self.response(record)
        }
        let treatment = IntakeRecord(id: UUID(), occurredAt: Self.at(15, 30), context: .hypoTreatment,
                                    items: [.init(id: UUID(), name: "포도당 캔디", count: 3, unit: "개")])
        intakes[treatment.id] = Self.response(treatment)
        // 지난 기록도 같은 목록에서 열 수 있게 한다.
        let old = IntakeRecord(id: UUID(), occurredAt: day.addingTimeInterval(-3600), context: .snack,
                               items: [.init(id: UUID(), name: "어제 간식", count: 1, unit: "개")])
        intakes[old.id] = Self.response(old)
        for (hour, minute, units) in [(8, 0, 4.0), (18, 50, 5.0)] {
            let id = UUID(), date = Self.at(hour, minute)
            insulins[id] = .init(id: id, occurredAt: date, units: units, kind: "직접 기록한 종류",
                                 createdAt: date, updatedAt: date)
        }
        if let image = ReportSamples.image(for: ReportSamples.photoID(1)), let data = image.jpegData(compressionQuality: 0.7) {
            photos.add(imageData: data, context: .meal, capturedAt: Self.at(12, 10))
        }
    }

    func fetchIntakePage(cursor: String?, limit: Int) async throws -> RecordPage {
        page(intakes.values.map { .intake($0.toRecord()) }, cursor: cursor, limit: limit)
    }
    func fetchInsulinPage(cursor: String?, limit: Int) async throws -> RecordPage {
        page(insulins.values.map { .insulin($0.toRecord()) }, cursor: cursor, limit: limit)
    }
    private func page(_ items: [RecordItem], cursor: String?, limit: Int) -> RecordPage {
        let items = items.sorted { $0.occurredAt == $1.occurredAt ? $0.id.uuidString < $1.id.uuidString : $0.occurredAt > $1.occurredAt }
        let offset = Int(cursor ?? "") ?? 0
        let slice = Array(items.dropFirst(offset).prefix(limit))
        return .init(items: slice, nextCursor: offset + slice.count < items.count ? String(offset + slice.count) : nil)
    }
    func get(id: UUID) async throws -> IntakeResponse {
        guard let record = intakes[id] else { throw APIError.invalidResponse }
        return record
    }
    func create(_ request: CreateIntakeRequest) async throws -> IntakeResponse {
        try await update(id: UUID(), request: request)
    }
    func update(id: UUID, request: CreateIntakeRequest) async throws -> IntakeResponse {
        let response = IntakeResponse(id: id, context: request.context, occurredAt: request.occurredAt,
            photoId: request.photoId, items: request.items.map {
                .init(id: UUID(), name: $0.name, count: $0.count, unit: $0.unit, categoryHint: $0.categoryHint, tags: $0.tags, sugarGrams: nil)
            }, createdAt: intakes[id]?.createdAt ?? .now, updatedAt: .now)
        intakes[id] = response
        return response
    }
    func create(_ request: InsulinEventRequest) async throws -> InsulinEventResponse {
        try await update(id: UUID(), request: request)
    }
    func update(id: UUID, request: InsulinEventRequest) async throws -> InsulinEventResponse {
        let response = InsulinEventResponse(id: id, occurredAt: request.occurredAt, units: request.units, kind: request.kind,
                                           createdAt: insulins[id]?.createdAt ?? .now, updatedAt: .now)
        insulins[id] = response
        return response
    }
    func delete(id: UUID) async throws { intakes[id] = nil; insulins[id] = nil }
    func recognize(photoId: UUID) async throws -> RecognitionResponse {
        .init(isFoodPhoto: true, items: [.init(name: "예시 음식", count: 1, unit: "개",
                                              categoryHint: nil, tags: [], confidence: "HIGH")], likelyConsumedAll: nil)
    }
    private static func at(_ hour: Int, _ minute: Int) -> Date {
        ReportDay.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: .now)!
    }
    private static func response(_ record: IntakeRecord) -> IntakeResponse {
        .init(id: record.id, context: record.context.rawValue, occurredAt: record.occurredAt, photoId: record.photoId,
              items: record.items.map { .init(id: $0.id, name: $0.name, count: $0.count, unit: $0.unit,
                                              categoryHint: $0.categoryHint, tags: $0.tags, sugarGrams: nil) },
              createdAt: record.occurredAt, updatedAt: record.occurredAt)
    }
}
#endif
