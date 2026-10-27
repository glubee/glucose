//
//  DayCloseStore.swift
//  glucose
//
//  하루 마무리를 끝낸 날. 연속 완성일(W5)이 이 기록을 쓴다.
//  지금은 기기에만 두고, 서버 day_close 테이블이 생기면 옮긴다(docs/ios-design-v4.md 5장 B단계).
//

import Foundation

@Observable
final class DayCloseStore {

    static let shared = DayCloseStore()

    /// 어제 마무리는 다음 날 이 시각(정오)까지 인정한다. 리브레 하루 그래프는 자정이 지나야 다 차기 때문
    static let graceHour = 12

    private(set) var closedDays: Set<String>

    private let defaults: UserDefaults
    private let key = "closed_days_v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        closedDays = Set(defaults.stringArray(forKey: key) ?? [])
    }

    func isClosed(_ day: Date) -> Bool {
        closedDays.contains(ReportDay.apiString(from: day))
    }

    func markClosed(_ day: Date) {
        closedDays.insert(ReportDay.apiString(from: day))
        defaults.set(Array(closedDays).sorted(), forKey: key)
    }

    /// 지금 마무리할 날: 정오 전이고 어제를 아직 안 했으면 어제, 아니면 오늘
    func targetDay(now: Date = .now) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ReportDay.timeZone
        let today = calendar.startOfDay(for: now)
        guard calendar.component(.hour, from: now) < Self.graceHour,
              let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              !isClosed(yesterday) else {
            return today
        }
        return yesterday
    }
}
