//
//  DemoDayCloseSync.swift
//  glucose
//
//  데모용(DEBUG 실행 인자 -demoSync). 하루 완성 벌집·연속 기록은 기기에만 저장되므로,
//  날짜를 옮긴 데모 계정(infra/demo-shift-dates.sh)으로 로그인한 뒤 서버에 그래프가 있는 날을 "완성"으로 채운다.
//  그래프가 절반 미만으로 읽힌 날은 "기록만 저장"으로 표시한다. 실제 사용자 흐름에서는 쓰지 않는다.
//

#if DEBUG
import Foundation

@MainActor
enum DemoDayCloseSync {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains { $0.lowercased() == "-demosync" } }

    /// 최근 `days`일(오늘 제외)을 서버 그래프 기준으로 다시 채운다
    /// 채운 날 수를 돌려준다
    @discardableResult
    static func run(days: Int = 42, store: DayCloseStore? = nil,
                    fetchCoverage: ((Date) async -> Double?)? = nil,
                    canCommit: (() -> Bool)? = nil, onSaved: (() -> Void)? = nil) async -> Int {
        let scope = DemoExecutionScope()
        let isCurrent = canCommit ?? { scope.isCurrent }
        guard isCurrent() else { return 0 }
        let calendar = ReportDay.calendar
        let today = calendar.startOfDay(for: .now)
        var found: [(day: Date, coverage: Double)] = []
        guard days > 0 else { return 0 }
        for offset in (1...days).reversed() {
            guard isCurrent() else { return 0 }
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let path = "/v1/glucose-readings/\(ReportDay.apiString(from: day))"
            if let fetchCoverage {
                if let coverage = await fetchCoverage(day) { found.append((day, coverage)) }
            } else if let readings: GlucoseReadings = try? await APIClient.shared.send(path: path) {
                found.append((day, readings.coverageRatio ?? 0))
            }
        }
        guard isCurrent() else { return 0 }
        let store = store ?? DayCloseStore.shared
        store.reset()
        for entry in found {
            store.markClosed(entry.day, recordOnly: entry.coverage < 0.5)
        }
        if let onSaved { onSaved() } else { WidgetSnapshot.refresh() }
        return found.count
    }
}
#endif
