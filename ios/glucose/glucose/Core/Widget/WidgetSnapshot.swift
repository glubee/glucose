//
//  WidgetSnapshot.swift
//  glucose
//
//  앱과 위젯이 App Group으로 나누는 값. 혈당·음식·인슐린 내용은 넣지 않는다(위젯은 잠금 화면에도 보임).
//  위젯 타깃의 GlubeeWidgets/WidgetSnapshot.swift와 같은 모양을 유지한다(타깃이 달라 파일을 나눠 둠).
//

import Foundation
import WidgetKit

struct WidgetSnapshot: Codable, Equatable {
    var streak = 0
    /// 오늘 마무리를 끝냈으면 그 날짜("yyyy-MM-dd")
    var closedDay: String?
    /// 마지막으로 기록(사진·인슐린·음식 확인)한 시각
    var lastRecordAt: Date?
    /// 쉬어가는 중이면 쉬는 마지막 날("yyyy-MM-dd")
    var restUntil: String?
    var dayCloseHour = 21
    var dayCloseMinute = 0

    static let appGroup = "group.com.glubee.glubee"
    private static let key = "widget_snapshot_v1"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func load() -> WidgetSnapshot {
        guard let data = defaults?.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return WidgetSnapshot() }
        return snapshot
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.defaults?.set(data, forKey: Self.key)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 앱의 현재 상태로 다시 쓴다. 기록을 남겼으면 noteRecord = true
    @MainActor
    static func refresh(noteRecord: Bool = false, now: Date = .now) {
        let store = DayCloseStore.shared
        let preferences = UserPreferences.shared
        let today = ReportDay.calendar.startOfDay(for: now)
        var snapshot = load()
        let previous = snapshot
        snapshot.streak = store.streak(endingAt: today)
        snapshot.closedDay = store.isClosed(today) ? ReportDay.apiString(from: today) : nil
        snapshot.restUntil = store.isResting(now: now) ? store.rest.map { ReportDay.apiString(from: $0.end) } : nil
        snapshot.dayCloseHour = preferences.dayCloseTime.hour ?? 21
        snapshot.dayCloseMinute = preferences.dayCloseTime.minute ?? 0
        if noteRecord { snapshot.lastRecordAt = now }
        if snapshot != previous { snapshot.save() }
        // 기록을 남기면 오늘 보채기 알림을 빼야 하므로 알림을 다시 짠다
        if noteRecord { Task { await NudgeScheduler.refresh() } }
    }

    /// 계정을 지웠을 때
    static func erase() {
        defaults?.removeObject(forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
