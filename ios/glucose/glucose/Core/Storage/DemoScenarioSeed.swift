//
//  DemoScenarioSeed.swift
//  glucose
//
//  데모용(DEBUG 실행 인자 -demoSeed). 데모 계정에 올린 리브레 그래프(원래 2026-09-07~10-10)의 곡선에 맞춰
//  식사·간식·저혈당 처치·술·인슐린 기록을 서버 API로 남긴다. 리포트 요약·음식별 관찰·주간 리포트를 보여주기 위한 것.
//  날짜는 "원래 그래프 날짜"로 적고, 서버에 있는 가장 최근 그래프 날짜를 10-10에 맞춰 옮긴다
//  (infra/demo-shift-dates.sh로 옮긴 뒤에도 맞는다). 이미 식사·인슐린 기록이 있는 날은 건너뛴다.
//  인슐린 단위는 기록 예시일 뿐 권장값이 아니다. 실제 사용자 계정에는 쓰지 않는다.
//

#if DEBUG
import Foundation

@MainActor
enum DemoScenarioSeed {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains { $0.lowercased() == "-demoseed" } }

    /// 화면에 보여줄 결과(혈당값·토큰은 담지 않는다)
    struct Report {
        var anchor: String?
        var created = 0
        var skippedDays: [String] = []
        var failures: [String] = []

        var text: String {
            guard let anchor else { return "최근 60일 안에서 그래프를 찾지 못했어요. 로그인 계정과 그래프 업로드를 확인해 주세요." }
            var lines = ["기준(가장 최근 그래프): \(anchor)", "새로 넣은 기록: \(created)건"]
            if !skippedDays.isEmpty { lines.append("이미 기록이 있어 건너뛴 날: \(skippedDays.joined(separator: ", "))") }
            if !failures.isEmpty { lines.append("실패 \(failures.count)건: \(failures.prefix(3).joined(separator: " / "))") }
            return lines.joined(separator: "\n")
        }
    }

    private struct Food {
        let name: String
        let count: Int
        let unit: String
        init(_ name: String, _ count: Int, _ unit: String) { self.name = name; self.count = count; self.unit = unit }
    }

    private enum Record {
        case intake(String, IntakeContext, [Food])
        case insulin(String, Double, String)
    }

    private static let rapid = "노보래피드"
    private static let basal = "트레시바"

    /// 원래 그래프 날짜 → 그날 기록(한국 시간 "HH:mm"). 그래프 곡선 모양에 맞춰 골랐다:
    /// 크게 오른 날은 인슐린 없는 고탄수 음식, 평탄한 날은 식사·인슐린 기록이 함께 있는 날,
    /// 기록 없이 새벽에 오른 날은 비워 둔다(새벽 공복 상승), 밤 술 → 다음 날 아침 낮은 값 등.
    private static let scenarios: [String: [Record]] = {
        let breakfast: [Food] = [Food("현미밥", 1, "공기"), Food("계란말이", 1, "접시")]
        let sandwich: [Food] = [Food("샌드위치", 1, "개"), Food("아메리카노", 1, "잔")]
        return [
            // 이번 주(옮긴 뒤 월·화)
            // 10/10: 아침은 거름(오전 내내 평탄), 점심 짜장면 + 인슐린 → 165까지, 오후 바나나
            "2026-10-10": [.insulin("13:10", 6, rapid), .intake("13:20", .meal, [Food("짜장면", 1, "그릇")]),
                           .intake("16:10", .snack, [Food("바나나", 1, "개")]),
                           .insulin("22:00", 14, basal)],
            // 10/9: 새벽 사과 주스(기록 없는 인슐린) → 5시 급상승, 저녁 떡볶이 + 인슐린 → 늦게 192
            "2026-10-09": [.intake("04:40", .snack, [Food("사과 주스", 1, "잔")]),
                           .insulin("17:20", 5, rapid), .intake("17:30", .meal, [Food("떡볶이", 1, "접시"), Food("튀김", 2, "개")]),
                           .insulin("22:00", 14, basal)],
            // 지난주
            // 10/8: 새벽 3~5시 기록 없이 상승(새벽 공복 상승), 아침·점심은 인슐린과 함께
            "2026-10-08": [.insulin("09:00", 4, rapid), .intake("09:10", .meal, breakfast),
                           .insulin("13:20", 6, rapid), .intake("13:30", .meal, [Food("비빔밥", 1, "그릇")]),
                           .insulin("22:00", 14, basal)],
            // 10/7: 오후 바나나(인슐린 없음) → 158, 저녁 인슐린 + 식사 → 80까지 내려감
            "2026-10-07": [.insulin("12:20", 4, rapid), .intake("12:30", .meal, sandwich),
                           .intake("14:40", .snack, [Food("바나나", 1, "개")]),
                           .insulin("17:10", 5, rapid), .intake("17:20", .meal, [Food("샐러드", 1, "그릇"), Food("닭가슴살", 1, "개")]),
                           .insulin("22:00", 14, basal)],
            // 10/6: 점심 제육 + 인슐린, 밤 초콜릿 → 174
            "2026-10-06": [.insulin("13:30", 6, rapid),
                           .intake("13:40", .meal, [Food("백미밥", 1, "공기"), Food("제육볶음", 1, "접시")]),
                           .intake("21:30", .snack, [Food("초콜릿", 2, "조각")]),
                           .insulin("22:00", 14, basal)],
            // 10/5: 아침·저녁 인슐린과 식사, 밤 치킨 + 맥주 → 23시 192, 다음 날 새벽까지 높음
            "2026-10-05": [.insulin("07:20", 4, rapid), .intake("07:30", .meal, breakfast),
                           .insulin("18:50", 5, rapid), .intake("19:00", .meal, [Food("백미밥", 1, "공기"), Food("김치찌개", 1, "그릇")]),
                           .intake("22:00", .alcohol, [Food("치킨", 3, "조각"), Food("맥주", 2, "캔")]),
                           .insulin("22:30", 14, basal)],
            // 10/4: 0~4시 기록 없이 120 → 196(새벽 공복 상승), 점심 샌드위치 + 인슐린
            "2026-10-04": [.insulin("12:00", 4, rapid), .intake("12:10", .meal, sandwich),
                           .insulin("17:00", 5, rapid), .intake("17:10", .meal, [Food("비빔밥", 1, "그릇")]),
                           .insulin("22:00", 14, basal)],
            // 그 전
            // 10/1: 점심 짜장면, 인슐린 기록 없음 → 212
            "2026-10-01": [.intake("13:20", .meal, [Food("짜장면", 1, "그릇"), Food("콜라", 1, "캔")])],
            // 9/30: 오후 콜라(인슐린 없음) → 188, 저녁 인슐린 + 피자 → 늦게 186
            "2026-09-30": [.intake("15:00", .snack, [Food("콜라", 1, "캔")]),
                           .insulin("20:50", 5, rapid), .intake("21:00", .meal, [Food("피자", 2, "조각")])],
            // 9/25: 점심 인슐린 + 샐러드 뒤 내려가 13:30 61 → 포도당 캔디로 빠르게 회복
            "2026-09-25": [.insulin("11:20", 4, rapid), .intake("11:30", .meal, [Food("샐러드", 1, "그릇")]),
                           .intake("13:40", .hypoTreatment, [Food("포도당 캔디", 3, "개")])],
            // 9/23: 아침 인슐린과 함께, 오후 떡볶이(인슐린 없음) → 214
            "2026-09-23": [.insulin("05:50", 4, rapid), .intake("06:00", .meal, breakfast),
                           .intake("15:00", .snack, [Food("떡볶이", 1, "접시")])],
            // 9/22: 세 끼 모두 인슐린과 함께 → 하루 내내 평탄
            "2026-09-22": [.insulin("09:20", 4, rapid), .intake("09:30", .meal, breakfast),
                           .insulin("15:20", 5, rapid), .intake("15:30", .meal, [Food("비빔밥", 1, "그릇")]),
                           .insulin("20:20", 5, rapid), .intake("20:30", .meal, [Food("백미밥", 1, "공기"), Food("김치찌개", 1, "그릇")]),
                           .insulin("22:30", 14, basal)],
            // 9/19: 전날 밤 술 → 아침 9:45 59, 초콜릿으로 대응 → 천천히 회복, 점심 인슐린과 함께
            "2026-09-19": [.intake("09:50", .hypoTreatment, [Food("초콜릿", 2, "조각")]),
                           .insulin("15:10", 6, rapid),
                           .intake("15:20", .meal, [Food("백미밥", 1, "공기"), Food("김치찌개", 1, "그릇")])],
            // 9/18: 밤 10시 치킨 + 맥주 → 23시 181
            "2026-09-18": [.intake("22:00", .alcohol, [Food("치킨", 3, "조각"), Food("맥주", 2, "캔")])],
            // 9/17: 점심 인슐린을 30분 늦게 → 14시 185
            "2026-09-17": [.insulin("07:00", 4, rapid), .intake("07:10", .meal, breakfast),
                           .intake("12:30", .meal, [Food("짜장면", 1, "그릇")]), .insulin("13:00", 6, rapid)],
            // 9/16: 4~6시 기록 없이 89 → 154(새벽 공복 상승), 밤 라면 → 188
            "2026-09-16": [.intake("22:30", .snack, [Food("라면", 1, "그릇")])],
            // 9/13: 점심 짜장면, 인슐린 기록 없음 → 224
            "2026-09-13": [.intake("13:40", .meal, [Food("짜장면", 1, "그릇")])],
            // 9/9: 아침 인슐린 뒤 11:30 69 → 오렌지 주스, 점심 인슐린 + 짜장면 → 189
            "2026-09-09": [.insulin("07:50", 4, rapid), .intake("08:00", .meal, breakfast),
                           .intake("11:35", .hypoTreatment, [Food("오렌지 주스", 1, "잔")]),
                           .insulin("13:10", 6, rapid), .intake("13:20", .meal, [Food("짜장면", 1, "그릇")])],
        ]
    }()

    private static let originalLastDay = "2026-10-10"

    @discardableResult
    static func run() async -> Report {
        var report = Report()
        let calendar = ReportDay.calendar
        guard let anchor = await latestGraphDay(),
              let originalLast = ReportDay.date(fromAPIString: originalLastDay),
              let shift = calendar.dateComponents([.day], from: originalLast, to: anchor).day else {
            print("[demoSeed] 그래프 없음")
            return report
        }
        report.anchor = ReportDay.apiString(from: anchor)

        for (originalDay, records) in scenarios.sorted(by: { $0.key < $1.key }) {
            guard let original = ReportDay.date(fromAPIString: originalDay),
                  let day = calendar.date(byAdding: .day, value: shift, to: original) else { continue }
            let dayString = ReportDay.apiString(from: day)
            if let daily: DailyReport = try? await APIClient.shared.send(path: "/v1/reports/daily/\(dayString)"),
               !daily.episodes.isEmpty || daily.insulinEventsCount > 0 {
                report.skippedDays.append(dayString)
                continue
            }
            for record in records {
                do {
                    try await post(record, on: day)
                    report.created += 1
                } catch {
                    report.failures.append("\(dayString) \(describe(error))")
                }
            }
        }
        print("[demoSeed] \(report.text)")
        WidgetSnapshot.refresh(noteRecord: true)
        return report
    }

    /// 시나리오 날짜(옮긴 뒤)에 있는 음식·인슐린 기록을 지운다. 데모 계정에서만 쓴다
    static func clear() async -> String {
        let calendar = ReportDay.calendar
        guard let anchor = await latestGraphDay(),
              let originalLast = ReportDay.date(fromAPIString: originalLastDay),
              let shift = calendar.dateComponents([.day], from: originalLast, to: anchor).day else {
            return "최근 60일 안에서 그래프를 찾지 못했어요."
        }
        let days = Set(scenarios.keys.compactMap { key -> String? in
            guard let original = ReportDay.date(fromAPIString: key),
                  let day = calendar.date(byAdding: .day, value: shift, to: original) else { return nil }
            return ReportDay.apiString(from: day)
        })
        let repository = LiveRecordRepository()
        var targets: [RecordItem] = []
        var cursor: String?
        repeat {
            guard let page = try? await repository.fetchIntakePage(cursor: cursor, limit: 100) else { break }
            targets += page.items.filter { days.contains(ReportDay.apiString(from: $0.occurredAt)) }
            cursor = page.nextCursor
        } while cursor != nil
        cursor = nil
        repeat {
            guard let page = try? await repository.fetchInsulinPage(cursor: cursor, limit: 100) else { break }
            targets += page.items.filter { days.contains(ReportDay.apiString(from: $0.occurredAt)) }
            cursor = page.nextCursor
        } while cursor != nil

        var removed = 0
        for item in targets {
            let path: String
            switch item {
            case .intake(let record): path = "/v1/intakes/\(record.id.uuidString)"
            case .insulin(let record): path = "/v1/insulin-events/\(record.id.uuidString)"
            }
            if (try? await APIClient.shared.sendVoid(path: path, method: .delete)) != nil { removed += 1 }
        }
        return "시나리오 날짜 \(days.count)일의 기록 \(removed)건을 지웠어요."
    }

    private static func post(_ record: Record, on day: Date) async throws {
        switch record {
        case .intake(let time, let context, let foods):
            guard let at = date(day, time) else { return }
            let request = CreateIntakeRequest(
                context: context.rawValue, occurredAt: at, photoId: nil,
                items: foods.map { IntakeItemRequest(name: $0.name, count: $0.count, unit: $0.unit, categoryHint: nil, tags: []) })
            let _: IntakeResponse = try await APIClient.shared.send(path: "/v1/intakes", method: .post, body: request)
        case .insulin(let time, let units, let kind):
            guard let at = date(day, time) else { return }
            let _: InsulinEventResponse = try await APIClient.shared.send(
                path: "/v1/insulin-events", method: .post, body: InsulinEventRequest(occurredAt: at, units: units, kind: kind))
        }
    }

    /// 오류 종류와 서버 오류 코드만(응답 원문은 남기지 않는다)
    private static func describe(_ error: Error) -> String {
        switch error {
        case APIError.server(let status, let body): "서버 \(status) \(body.code)"
        case APIError.notAuthenticated: "로그인 필요"
        case APIError.decoding: "응답 해석 실패(기록은 들어갔을 수 있음)"
        case APIError.network: "네트워크"
        default: "알 수 없음"
        }
    }

    private static func date(_ day: Date, _ time: String) -> Date? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return ReportDay.calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }

    /// 최근 60일 중 그래프가 있는 가장 늦은 날
    private static func latestGraphDay() async -> Date? {
        let calendar = ReportDay.calendar
        let today = calendar.startOfDay(for: .now)
        for offset in 0...60 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            if (try? await APIClient.shared.send(path: "/v1/glucose-readings/\(ReportDay.apiString(from: day))") as GlucoseReadings) != nil {
                return day
            }
        }
        return nil
    }
}
#endif
