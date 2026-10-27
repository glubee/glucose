//
//  NudgeScheduler.swift
//  glucose
//
//  글루비 알림(디자이너 v5 "알림 문구 톤"). 앱을 열거나 기록할 때마다 앞으로 7일치를 지우고 다시 예약한다.
//  그 뒤로 앱을 안 열면 예약된 알림이 차례로 나간다: 다음 날 아침 시무룩(꿀단지가 있으면 꿀단지),
//  2~3일째 화남(귀엽게), 7일째 잠듦. 7일 넘게 안 오면 더 보내지 않는다.
//
//  규칙(보드 "보내는 규칙과 쓰지 않는 말"):
//  - 혈당 수치·높음/낮음, 먹은 음식, 인슐린 이름·단위를 넣지 않는다(잠금 화면에 보임)
//  - 기록을 했는지·마무리를 했는지·며칠째 안 왔는지에만 반응한다
//  - 하루 최대 2번(마무리 1 + 감정 1). 보채기를 보낸 날에는 조마조마를 보내지 않는다
//  - 쉬어가는 중엔 보내지 않고, 끝난 다음 날 아침에 "다시 만나요" 한 번만
//  - 23시~8시에는 보내지 않는다(조마조마는 22:59까지)
//

import Foundation
import UserNotifications

enum NudgeScheduler {

    static let identifierPrefix = "glubee-nudge-"
    static let deepLink = "glubee://day-close"
    private static let homeLink = "glubee://home"
    private static let daysAhead = 7
    /// 이 시각 전에 오늘 기록이 없으면 보채기
    private static let nagHour = 15

    private struct Nudge {
        let id: String
        let fire: Date
        let title: String
        let body: String
        let url: String
    }

    @MainActor
    static func refresh(
        preferences: UserPreferences = .shared,
        store: DayCloseStore = .shared,
        now: Date = .now
    ) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter {
            $0.hasPrefix(identifierPrefix) || $0.hasPrefix("day-close-") // 예전 이름
        })
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }

        for nudge in plan(preferences: preferences, store: store, now: now) where nudge.fire > now {
            let content = UNMutableNotificationContent()
            content.title = nudge.title
            content.body = nudge.body
            content.sound = .default
            content.userInfo = ["url": nudge.url]
            let components = ReportDay.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: nudge.fire)
            let request = UNNotificationRequest(
                identifier: identifierPrefix + nudge.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    /// 앞으로 7일 동안 앱을 열지 않는다고 보고 짠 알림 계획
    @MainActor
    private static func plan(preferences: UserPreferences, store: DayCloseStore, now: Date) -> [Nudge] {
        let calendar = ReportDay.calendar
        let today = calendar.startOfDay(for: now)
        let time = preferences.dayCloseTime
        let streak = store.streak(endingAt: today)
        let recordedToday = WidgetSnapshot.load().lastRecordAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false

        func at(_ day: Date, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        /// 23시~8시를 피한다
        func clamp(_ date: Date) -> Date {
            let hour = calendar.component(.hour, from: date)
            if hour >= 23 { return at(date, 22, 59) }
            if hour < 8 { return at(date, 8) }
            return date
        }

        // 며칠째 안 왔는지는 오늘부터, 쉬는 중이면 쉬기가 끝난 다음 날부터 센다
        var absenceStart = today
        if let rest = store.rest, store.isRest(today),
           let afterRest = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: rest.end)) {
            absenceStart = afterRest
        }

        var nudges: [Nudge] = []
        for offset in 0..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let dayKey = ReportDay.apiString(from: day)

            // 쉬는 중엔 보내지 않는다
            if store.isRest(day) { continue }

            let closeAt = clamp(at(day, time.hour ?? 21, time.minute ?? 0))
            let closed = store.isClosed(day)

            // 평온: 매일 마무리 시각에 한 번
            if !closed {
                nudges.append(Nudge(id: "close-\(dayKey)", fire: closeAt,
                                    title: "하루 마무리할 시간이에요", body: "오늘 칸을 같이 채워요. 1분이면 돼요.", url: deepLink))
            }

            // 감정 알림은 하루 한 번만
            let away = calendar.dateComponents([.day], from: absenceStart, to: day).day ?? 0
            if absenceStart != today && away == 0 {
                // 쉬기가 끝난 다음 날 아침에만 한 번
                nudges.append(Nudge(id: "rest-over-\(dayKey)", fire: at(day, 9),
                                    title: "다시 만나요", body: "오늘부터 다시 같이 모아요. 천천히 와도 돼요.", url: homeLink))
            } else if absenceStart == today && away == 0 {
                let nagAt = at(day, nagHour)
                if !recordedToday && !closed && now < nagAt {
                    nudges.append(Nudge(id: "nag-\(dayKey)", fire: nagAt,
                                        title: "오늘 아직 한 칸도 없어요!", body: "하나만 남겨줄래요? 사진 한 장이면 돼요.", url: homeLink))
                } else if !closed && streak > 0 {
                    // 조마조마: 마무리 시각 1시간 뒤(22:59까지). 보채기를 보낸 날엔 보내지 않는다
                    let anxiousAt = clamp(closeAt.addingTimeInterval(3600))
                    nudges.append(Nudge(id: "anxious-\(dayKey)", fire: anxiousAt,
                                        title: "오늘이 곧 끝나요",
                                        body: "연속 \(streak + 1)일째가 될 칸이 아직 비어 있어요. 같이 채울 거죠?", url: deepLink))
                }
            } else if away == 1 {
                // 전날 마무리를 놓친 다음 날 아침
                guard let previous = calendar.date(byAdding: .day, value: -1, to: day), !store.isClosed(previous) else { continue }
                let honeypots = store.honeypots
                nudges.append(honeypots > 0
                    ? Nudge(id: "honeypot-\(dayKey)", fire: at(day, 9), title: "꿀단지가 연속을 지켜줘요",
                            body: "어제 칸을 꿀단지가 채워요. 남은 꿀단지 \(honeypots - 1)개.", url: homeLink)
                    : Nudge(id: "sulky-\(dayKey)", fire: at(day, 9), title: "어제는 쉬어갔네요",
                            body: "괜찮아요. 오늘 다시 같이 모아요.", url: homeLink))
            } else if away == 2 || away == 3 {
                nudges.append(Nudge(id: "angry-\(dayKey)", fire: at(day, 19),
                                    title: away == 2 ? "흥, 이틀째 기다렸어요" : "흥, 사흘째 기다렸어요",
                                    body: "얼굴 한 번만 보여줘요. 그럼 풀릴게요.", url: homeLink))
            } else if away == 6 {
                nudges.append(Nudge(id: "sleep-\(dayKey)", fire: at(day, 19),
                                    title: "글루비가 꿀단지 베고 자고 있어요",
                                    body: "깨우러 와줄래요? 천천히 와도 돼요.", url: homeLink))
            }
        }
        return nudges
    }

    #if DEBUG
    /// 시뮬레이터 확인용: 실행 인자 -printNudges
    @MainActor
    static func debugPrintPlan(now: Date = .now) {
        let formatter = DateFormatter()
        formatter.timeZone = ReportDay.timeZone
        formatter.dateFormat = "MM-dd(E) HH:mm"
        formatter.locale = Locale(identifier: "ko_KR")
        for nudge in plan(preferences: .shared, store: .shared, now: now) where nudge.fire > now {
            print("[nudge]", formatter.string(from: nudge.fire), nudge.title, "/", nudge.body)
        }
        fflush(stdout)
    }
    #endif
}
