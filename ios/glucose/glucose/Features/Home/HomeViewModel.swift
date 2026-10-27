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

    init(now: Date = .now, store: DayCloseStore = .shared, photos: PendingPhotoStore = .shared,
         preferences: UserPreferences = .shared) {
        today = ReportDay.calendar.startOfDay(for: now)
        report = DailyReportViewModel(day: today)
        self.store = store
        self.photos = photos
        self.preferences = preferences
    }

    var nickname: String { preferences.nickname }
    var streak: Int { store.streak(endingAt: today) }
    var honeypots: Int { store.honeypots }
    var weekStates: [HoneyCellState] { store.weekStates(containing: today) }
    var rest: RestPeriod? { store.isResting() ? store.rest : nil }
    var isTodayClosed: Bool { store.isClosed(today) }

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

    /// 글루비 기분과 한마디. 기록 여부와 시각에만 반응한다
    func mood(now: Date = .now) -> (pose: MascotPose, line: String) {
        if rest != nil { return (.breakTime, "천천히 와도 돼요") }
        if isTodayClosed { return (.happy, "오늘 칸을 채웠어요. 내일 또 만나요.") }
        let hour = ReportDay.calendar.component(.hour, from: now)
        if isPastDayClose(now: now) {
            return streak > 0
                ? (.anxious, "연속 \(streak)일이 오늘 칸을 기다려요.")
                : (.clock, "하루 마무리할 시간이에요.")
        }
        if todayRecordCount > 0 { return (.wave, "좋아요, 오늘도 하나씩 모이고 있어요.") }
        if hour >= 13 { return (.nag, "오늘 아직 한 칸도 없어요! 사진 한 장만요.") }
        return (.wave, "오늘도 하나씩 모아볼까요?")
    }

    func refresh() async {
        await report.load()
        WidgetSnapshot.refresh()
    }

    func startRest(_ reason: RestPeriod.Reason, days: Int) async {
        store.startRest(reason, days: days)
        WidgetSnapshot.refresh()
        await DayCloseReminder.refresh()
    }

    func endRest() async {
        store.endRest()
        WidgetSnapshot.refresh()
        await DayCloseReminder.refresh()
    }
}
