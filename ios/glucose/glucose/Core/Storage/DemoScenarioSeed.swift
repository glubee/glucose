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
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-demoSeed") }

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

    /// 원래 그래프 날짜 → 그날 기록(한국 시간 "HH:mm")
    private static let scenarios: [String: [Record]] = {
        let breakfast: [Food] = [Food("현미밥", 1, "공기"), Food("계란말이", 1, "접시")]
        let sandwich: [Food] = [Food("샌드위치", 1, "개"), Food("아메리카노", 1, "잔")]
        return [
            // 이번 주(옮긴 뒤 월·화)
            "2026-10-10": [.insulin("08:20", 4, rapid), .intake("08:30", .meal, breakfast),
                           .insulin("13:10", 6, rapid), .intake("13:20", .meal, [Food("짜장면", 1, "그릇")]),
                           .intake("16:10", .snack, [Food("바나나", 1, "개")]),
                           .insulin("22:00", 14, basal)],
            "2026-10-09": [.insulin("07:40", 4, rapid), .intake("07:50", .meal, breakfast),
                           .insulin("18:20", 6, rapid),
                           .intake("18:30", .meal, [Food("백미밥", 1, "공기"), Food("김치찌개", 1, "그릇")]),
                           .insulin("22:00", 14, basal)],
            // 지난주
            "2026-10-08": [.insulin("08:30", 4, rapid), .intake("08:40", .meal, breakfast),
                           .insulin("13:20", 6, rapid), .intake("13:30", .meal, [Food("비빔밥", 1, "그릇")]),
                           .insulin("22:00", 14, basal)],
            "2026-10-07": [.insulin("12:20", 4, rapid), .intake("12:30", .meal, sandwich),
                           .intake("15:00", .snack, [Food("바나나", 1, "개")]),
                           .insulin("22:00", 14, basal)],
            "2026-10-06": [.insulin("13:20", 6, rapid),
                           .intake("13:30", .meal, [Food("백미밥", 1, "공기"), Food("제육볶음", 1, "접시")]),
                           .intake("21:30", .snack, [Food("초콜릿", 2, "조각")]),
                           .insulin("22:00", 14, basal)],
            "2026-10-05": [.insulin("07:50", 4, rapid), .intake("08:00", .meal, breakfast),
                           .insulin("13:20", 6, rapid), .intake("13:30", .meal, [Food("짜장면", 1, "그릇")]),
                           .intake("22:30", .snack, [Food("초콜릿", 2, "조각")]),
                           .insulin("22:00", 14, basal)],
            "2026-10-04": [.insulin("12:20", 4, rapid), .intake("12:30", .meal, sandwich),
                           .intake("16:30", .snack, [Food("바나나", 1, "개")]),
                           .insulin("22:00", 14, basal)],
            // 그 전: 저혈당 처치·술
            "2026-10-01": [.insulin("13:30", 6, rapid), .intake("13:40", .meal, [Food("짜장면", 1, "그릇")])],
            "2026-09-25": [.insulin("07:50", 4, rapid), .intake("08:00", .meal, breakfast),
                           .intake("13:40", .hypoTreatment, [Food("포도당 캔디", 3, "개"), Food("오렌지 주스", 1, "잔")])],
            "2026-09-23": [.insulin("14:50", 5, rapid), .intake("15:00", .meal, [Food("떡볶이", 1, "접시")]),
                           .intake("17:30", .alcohol, [Food("맥주", 2, "캔")])],
            "2026-09-19": [.intake("09:50", .hypoTreatment, [Food("포도당 캔디", 4, "개")]),
                           .insulin("15:10", 6, rapid),
                           .intake("15:20", .meal, [Food("백미밥", 1, "공기"), Food("김치찌개", 1, "그릇")])],
            "2026-09-09": [.intake("11:35", .hypoTreatment, [Food("오렌지 주스", 1, "잔")]),
                           .insulin("14:10", 6, rapid), .intake("14:20", .meal, [Food("짜장면", 1, "그릇")])],
        ]
    }()

    private static let originalLastDay = "2026-10-10"

    /// 넣은 기록 수(이미 기록이 있어 건너뛴 날은 빼고)
    @discardableResult
    static func run() async -> Int {
        let calendar = ReportDay.calendar
        guard let anchor = await latestGraphDay(),
              let originalLast = ReportDay.date(fromAPIString: originalLastDay),
              let shift = calendar.dateComponents([.day], from: originalLast, to: anchor).day else { return 0 }

        var created = 0
        for (originalDay, records) in scenarios.sorted(by: { $0.key < $1.key }) {
            guard let original = ReportDay.date(fromAPIString: originalDay),
                  let day = calendar.date(byAdding: .day, value: shift, to: original) else { continue }
            let dayString = ReportDay.apiString(from: day)
            if let report: DailyReport = try? await APIClient.shared.send(path: "/v1/reports/daily/\(dayString)"),
               !report.episodes.isEmpty || report.insulinEventsCount > 0 {
                continue
            }
            for record in records {
                if await post(record, on: day) { created += 1 }
            }
        }
        WidgetSnapshot.refresh(noteRecord: true)
        return created
    }

    private static func post(_ record: Record, on day: Date) async -> Bool {
        switch record {
        case .intake(let time, let context, let foods):
            guard let at = date(day, time) else { return false }
            let request = CreateIntakeRequest(
                context: context.rawValue, occurredAt: at, photoId: nil,
                items: foods.map { IntakeItemRequest(name: $0.name, count: $0.count, unit: $0.unit, categoryHint: nil, tags: []) })
            let response: IntakeResponse? = try? await APIClient.shared.send(path: "/v1/intakes", method: .post, body: request)
            return response != nil
        case .insulin(let time, let units, let kind):
            guard let at = date(day, time) else { return false }
            let response: InsulinEventResponse? = try? await APIClient.shared.send(
                path: "/v1/insulin-events", method: .post, body: InsulinEventRequest(occurredAt: at, units: units, kind: kind))
            return response != nil
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
