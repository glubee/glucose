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

    private(set) var today: Date
    /// 홈 다이어리에 펼친 날(기본 오늘). 지난 날도 같은 줄노트로 볼 수 있다
    private(set) var diaryDay: Date
    var isDiaryToday: Bool { diaryDay == today }
    var canDiaryGoForward: Bool { diaryDay < today }
    private(set) var report: DailyReportViewModel
    let timeline: TodayTimelineViewModel

    private let store: DayCloseStore
    let photos: PendingPhotoStore
    private let preferences: UserPreferences
    /// 앱을 연 시점의 마지막 기록 시각(며칠째 안 왔는지)
    private let lastRecordAt: Date?

    init(now: Date = .now, store: DayCloseStore? = nil, photos: PendingPhotoStore? = nil,
         preferences: UserPreferences? = nil, repository: RecordRepository? = nil) {
        let day = ReportDay.calendar.startOfDay(for: now)
        today = day
        diaryDay = day
        report = DailyReportViewModel(day: day)
        timeline = TodayTimelineViewModel(repository: repository)
        self.store = store ?? RecordDataSource.dayClose
        self.photos = photos ?? RecordDataSource.photos
        self.preferences = preferences ?? RecordDataSource.preferences
        lastRecordAt = RecordDataSource.isPreview ? nil : WidgetSnapshot.load().lastRecordAt
    }

    var nickname: String { preferences.nickname }
    var streak: Int { store.streak(endingAt: today) }
    var honeypots: Int { store.honeypots }
    var weekStates: [HoneyCellState] { store.weekStates(containing: today) }
    var rest: RestPeriod? { store.isResting() ? store.rest : nil }
    var isTodayClosed: Bool { store.isClosed(today) }
    /// 다이어리에 펼친 날을 이미 마무리했는지
    var isDiaryDayClosed: Bool { store.isClosed(diaryDay) }

    /// 위젯으로 찍고 아직 확인하지 않은 사진 수(날짜 상관없이)
    var pendingPhotoCount: Int { photos.photos.count }

    var todayEntries: [TimelineEntry] { timeline.entries(photos: photos.photos) }
    var todayRecordCount: Int { todayEntries.count }

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
        return todayEntries.map { entry in
            let isInsulin: Bool
            if case .record(.insulin) = entry { isInsulin = true }
            else { isInsulin = false }
            return (position(entry.occurredAt), isInsulin)
        }
    }

    /// returnToToday: 새 기록을 남긴 뒤처럼 오늘 다이어리로 돌아와야 할 때
    func refresh(now: Date = .now, returnToToday: Bool = false) async {
        let day = ReportDay.calendar.startOfDay(for: now)
        if day != today {
            if diaryDay == today { diaryDay = day }
            today = day
            report = DailyReportViewModel(day: day)
        }
        if returnToToday { diaryDay = today }
        let daily = report
        async let reportLoad: Void = daily.load()
        await timeline.load(day: diaryDay)
        await reportLoad
        guard !Task.isCancelled else { return }
        timeline.prepareFocus(changes: .shared, photos: photos.photos)
        if !RecordDataSource.isPreview { WidgetSnapshot.refresh() }
    }

    /// 다이어리를 다른 날로 펼친다(오늘 이후는 안 됨)
    func showDiary(day: Date) async {
        diaryDay = min(ReportDay.calendar.startOfDay(for: day), today)
        await timeline.load(day: diaryDay)
    }

    func moveDiary(byDays days: Int) async {
        guard let day = ReportDay.calendar.date(byAdding: .day, value: days, to: diaryDay) else { return }
        await showDiary(day: day)
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
