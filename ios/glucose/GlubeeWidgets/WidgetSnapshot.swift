//
//  WidgetSnapshot.swift
//  GlubeeWidgets
//
//  앱이 App Group에 써 둔 값(앱 타깃 Core/Widget/WidgetSnapshot.swift와 같은 모양)과,
//  그 값으로 위젯 글루비 얼굴을 고르는 규칙. 글루비는 기록을 했는지에만 반응한다.
//

import Foundation

struct WidgetSnapshot: Codable, Equatable {
    var streak = 0
    var closedDay: String?
    var lastRecordAt: Date?
    var restUntil: String?
    var dayCloseHour = 21
    var dayCloseMinute = 0

    static let appGroup = "group.com.glubee.glubee"
    private static let key = "widget_snapshot_v1"

    static func load() -> WidgetSnapshot {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return WidgetSnapshot() }
        return snapshot
    }
}

enum WidgetMood {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func closeTime(_ snapshot: WidgetSnapshot, on date: Date) -> Date {
        calendar.date(bySettingHour: snapshot.dayCloseHour, minute: snapshot.dayCloseMinute, second: 0, of: date) ?? date
    }

    /// 얼굴 이름(face_*). 혈당·음식·용량에는 반응하지 않는다
    static func face(_ snapshot: WidgetSnapshot, at date: Date) -> String {
        let today = dayString(date)
        if let restUntil = snapshot.restUntil, today <= restUntil { return "sleep" }
        if snapshot.closedDay == today { return "celebrate" }
        if let last = snapshot.lastRecordAt, calendar.isDate(last, inSameDayAs: date) { return "calm" }
        if date >= closeTime(snapshot, on: date), snapshot.streak > 0 { return "anxious" }
        if calendar.component(.hour, from: date) >= 13 { return "nag" }
        return "calm"
    }

    /// 얼굴이 바뀔 수 있는 시각들: 13시, 마무리 시각, 다음 날 0시
    static func changePoints(after date: Date, snapshot: WidgetSnapshot) -> [Date] {
        let start = calendar.startOfDay(for: date)
        let candidates = [
            calendar.date(bySettingHour: 13, minute: 0, second: 0, of: date),
            closeTime(snapshot, on: date),
            calendar.date(byAdding: .day, value: 1, to: start),
        ].compactMap { $0 }
        return candidates.filter { $0 > date }.sorted()
    }
}
