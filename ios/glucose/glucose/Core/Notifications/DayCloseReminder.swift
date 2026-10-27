//
//  DayCloseReminder.swift
//  glucose
//
//  하루 마무리 알림(기본 21:00). 앞으로 7일치를 지우고 다시 예약하며, 이미 마무리한 날은 건너뛴다.
//  알림 문구에 혈당·음식·인슐린 내용을 넣지 않는다(잠금 화면에 보임).
//  W6에서 글루비 감정·활동 없음 알림으로 넓힌다.
//

import Foundation
import UserNotifications

enum DayCloseReminder {

    static let identifierPrefix = "day-close-"
    static let deepLink = "glubee://day-close"
    private static let daysAhead = 7

    static func refresh(
        preferences: UserPreferences = .shared,
        store: DayCloseStore = .shared,
        now: Date = .now
    ) async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }

        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ReportDay.timeZone
        let time = preferences.dayCloseTime
        let today = calendar.startOfDay(for: now)

        for offset in 0..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  !store.isClosed(day), !store.isRest(day),
                  let fireDate = calendar.date(bySettingHour: time.hour ?? 21, minute: time.minute ?? 0,
                                               second: 0, of: day),
                  fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "글루비"
            content.body = "오늘 하루를 같이 마무리해요."
            content.sound = .default
            content.userInfo = ["url": deepLink]

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let request = UNNotificationRequest(
                identifier: identifierPrefix + ReportDay.apiString(from: day),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }
}
