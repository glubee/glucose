//
//  HomeViewModel.swift
//  glucose
//
//  홈(v5): 연속 완성일, 이번 주 벌집, 꿀단지, 오늘의 흐름, 글루비 기분.
//  글루비는 기록을 했는지에만 반응한다. 혈당 수치·음식·인슐린 용량에는 반응하지 않는다(0-1장).
//

import Foundation

@MainActor
@Observable
final class HomeViewModel {

    let today: Date
    let report: DailyReportViewModel

    private let store: DayCloseStore
    private let photos: PendingPhotoStore
    private let preferences: UserPreferences
    /// 앱을 연 시점의 마지막 기록 시각(며칠째 안 왔는지)
    private let lastRecordAt: Date?

    init(now: Date = .now, store: DayCloseStore = .shared, photos: PendingPhotoStore = .shared,
         preferences: UserPreferences = .shared) {
        today = ReportDay.calendar.startOfDay(for: now)
        report = DailyReportViewModel(day: today)
        self.store = store
        self.photos = photos
        self.preferences = preferences
        lastRecordAt = WidgetSnapshot.load().lastRecordAt
    }

    var nickname: String { preferences.nickname }
    var streak: Int { store.streak(endingAt: today) }
    var honeypots: Int { store.honeypots }
    var weekStates: [HoneyCellState] { store.weekStates(containing: today) }
    var rest: RestPeriod? { store.isResting() ? store.rest : nil }
    var isTodayClosed: Bool { store.isClosed(today) }

    /// 위젯으로 찍고 아직 확인하지 않은 사진 수(날짜 상관없이)
    var pendingPhotoCount: Int { photos.photos.count }

    /// 오늘 남긴 기록 수(저장된 식사 묶음 + 인슐린 + 확인 대기 사진)
    var todayRecordCount: Int {
        let pending = photos.photos.filter { ReportDay.calendar.isDate($0.capturedAt, inSameDayAs: today) }.count
        guard case .loaded(let dailyReport, _) = report.state else { return pending }
        return dailyReport.episodes.count + dailyReport.insulinEventsCount + pending
    }

    var restEndText: String? {
        guard let rest else { return nil }
        return ReportDay.displayString(from: rest.end)
    }

    /// 하루 마무리 시각이 지났는지
    func isPastDayClose(now: Date = .now) -> Bool {
        let time = preferences.dayCloseTime
        let calendar = ReportDay.calendar
        guard let closeTime = calendar.date(bySettingHour: time.hour ?? 21, minute: time.minute ?? 0,
                                            second: 0, of: now) else { return false }
        return now >= closeTime
    }

    /// 마지막 기록에서 며칠 지났는지(앱을 연 지금 기준, 오늘 기록이면 0)
    private var daysSinceLastRecord: Int? {
        guard let last = lastRecordAt else { return nil }
        let calendar = ReportDay.calendar
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: today).day
    }

    /// 글루비 기분·움직임·한마디(디자이너 v5 프로토타입 문구). 기록 여부와 시각에만 반응한다
    func mood(now: Date = .now) -> (pose: MascotPose, motion: MascotMotion, line: String) {
        if rest != nil { return (.breakTime, .pop, "천천히 와도 돼요") }
        if isTodayClosed { return (.happy, .jump, "오늘 칸을 채웠어요. 내일 또 만나요.") }
        let recordedToday = todayRecordCount > 0
        if !recordedToday, let days = daysSinceLastRecord {
            if days >= 7 { return (.sleep, .pop, "쿨… 천천히 와도 돼요.") }
            if days >= 2 { return (.angry, .shake, days == 2 ? "흥, 이틀째 기다렸어요." : "흥, 사흘째 기다렸어요.") }
        }
        if isPastDayClose(now: now) && streak > 0 { return (.anxious, .pop, "오늘이 곧 끝나요. 같이 채울 거죠?") }
        if !recordedToday {
            let yesterday = ReportDay.calendar.date(byAdding: .day, value: -1, to: today) ?? today
            let hour = ReportDay.calendar.component(.hour, from: now)
            if hour < 13, !store.isClosed(yesterday), !store.isRest(yesterday), daysSinceLastRecord != nil {
                return (.sulky, .pop, "어제는 쉬어갔네요. 오늘 다시 모아요.")
            }
            if hour >= 13 { return (.nag, .jump, "오늘 아직 한 칸도 없어요! 하나만 남겨줄래요?") }
        }
        let name = nickname.isEmpty ? "" : "\(nickname)님, "
        return (.wave, .pop, "\(name)오늘도 하나씩 모아볼까요?")
    }

    /// 오늘의 흐름 카드에 찍을 점(하루 중 위치 0~1, 인슐린인지)
    var todayDots: [(position: Double, isInsulin: Bool)] {
        let calendar = ReportDay.calendar
        func position(_ date: Date) -> Double {
            Double(calendar.dateComponents([.minute], from: today, to: date).minute ?? 0) / 1440
        }
        var dots = photos.photos
            .filter { calendar.isDate($0.capturedAt, inSameDayAs: today) }
            .map { (position($0.capturedAt), false) }
        if case .loaded(let dailyReport, _) = report.state {
            dots += dailyReport.episodes.map { (position($0.startAt), false) }
            dots += (dailyReport.insulinEvents ?? []).map { (position($0.occurredAt), true) }
        }
        return dots.filter { $0.0 >= 0 && $0.0 <= 1 }
    }

    func refresh() async {
        await report.load()
        WidgetSnapshot.refresh()
    }

    func startRest(_ reason: RestPeriod.Reason, days: Int) async {
        store.startRest(reason, days: days)
        WidgetSnapshot.refresh()
        await NudgeScheduler.refresh()
    }

    func endRest() async {
        store.endRest()
        WidgetSnapshot.refresh()
        await NudgeScheduler.refresh()
    }
}
