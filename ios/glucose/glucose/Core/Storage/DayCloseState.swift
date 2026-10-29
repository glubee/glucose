import Foundation

struct RestPeriod: Codable, Equatable {
    enum Reason: String, Codable, CaseIterable {
        case resting, unwell, noSensor

        var title: String {
            switch self {
            case .resting: "쉬는 중"
            case .unwell: "몸이 안 좋아요"
            case .noSensor: "센서 없음"
            }
        }
    }

    let reason: Reason
    /// 쉬기 시작한 날
    let start: Date
    /// 쉬는 마지막 날(포함)
    let end: Date
}

/// Pure local projection. Wire dates use yyyy-MM-dd, never Date's Codable representation.
struct DayCloseState: Codable, Equatable {
    var closedDays: Set<String> = []
    var recordOnlyDays: Set<String> = []
    var honeypotSavedDays: Set<String> = []
    var honeypots = 0
    var rest: RestPeriod?
    var lastHoneypotUse: String?
    private var calendar: Calendar { ReportDay.calendar }
    private func key(_ day: Date) -> String { ReportDay.apiString(from: day) }

    private func milestoneCount() -> Int {
        var run = 0, total = 0
        var previous: Date?
        for key in closedDays.sorted() {
            guard let day = ReportDay.date(fromAPIString: key) else { continue }
            if let previous {
                var gap = calendar.date(byAdding: .day, value: 1, to: previous)!
                while gap < day {
                    if !isSavedByHoneypot(gap) && !isRest(gap) { run = 0; break }
                    gap = calendar.date(byAdding: .day, value: 1, to: gap)!
                }
            }
            run += 1
            if run % 7 == 0 { total += 1 }
            previous = day
        }
        return total
    }
    // MARK: - 하루 상태

    func isClosed(_ day: Date) -> Bool { closedDays.contains(key(day)) }
    func isSavedByHoneypot(_ day: Date) -> Bool { honeypotSavedDays.contains(key(day)) }

    func isRest(_ day: Date) -> Bool {
        guard let rest = rest else { return false }
        let d = calendar.startOfDay(for: day)
        return d >= calendar.startOfDay(for: rest.start) && d <= calendar.startOfDay(for: rest.end)
    }

    func isResting(now: Date = .now) -> Bool { isRest(now) }

    mutating func markClosed(_ day: Date, recordOnly: Bool = false) {
        let dayKey = key(day)
        let before = milestoneCount()
        let inserted = closedDays.insert(dayKey).inserted
        honeypotSavedDays.remove(dayKey)
        if !recordOnly { recordOnlyDays.remove(dayKey) }
        else if inserted { recordOnlyDays.insert(dayKey) }
        honeypots = min(2, honeypots + max(0, milestoneCount() - before))
    }

    // MARK: - 연속

    /// day까지 이어진 연속 완성일 수. day를 아직 안 했으면 그 전날까지 센다.
    /// 꿀단지로 지킨 날·쉬어간 날은 연속을 잇되 숫자를 늘리지 않는다
    func streak(endingAt day: Date) -> Int {
        var cursor = calendar.startOfDay(for: day)
        if !isClosed(cursor), let previous = calendar.date(byAdding: .day, value: -1, to: cursor) {
            cursor = previous
        }
        var count = 0
        // 쉬어가기·꿀단지가 아주 길게 이어져도 끝나도록 1년으로 제한
        for _ in 0..<366 {
            if isClosed(cursor) {
                count += 1
            } else if !(isSavedByHoneypot(cursor) || isRest(cursor)) {
                break
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    /// 지금 마무리할 날: 정오 전이고 어제를 아직 안 했으면 어제, 아니면 오늘
    func targetDay(now: Date = .now) -> Date {
        let today = calendar.startOfDay(for: now)
        guard calendar.component(.hour, from: now) < DayCloseStore.graceHour,
              let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              !isClosed(yesterday), !isRest(yesterday) else {
            return today
        }
        return yesterday
    }

    /// 유예가 지난 빠진 날에 꿀단지를 쓴다. 앱이 열릴 때마다 부른다. 쓴 날 수를 돌려준다
    @discardableResult
    mutating func applyHoneypots(now: Date = .now) -> Int {
        guard honeypots > 0 else { return 0 }
        // 이미 마감된 마지막 날: 유예 중이면 그저께, 아니면 어제
        let today = calendar.startOfDay(for: now)
        let inGrace = calendar.component(.hour, from: now) < DayCloseStore.graceHour
        guard let lastDeadlinePassed = calendar.date(byAdding: .day, value: inGrace ? -2 : -1, to: today) else { return 0 }

        // 마지막으로 완성·보호·쉬어간 날 다음부터 빠진 날을 찾는다(최근 14일만)
        var missed: [Date] = []
        var cursor = lastDeadlinePassed
        for _ in 0..<14 {
            if isClosed(cursor) || isSavedByHoneypot(cursor) || isRest(cursor) { break }
            missed.insert(cursor, at: 0)
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        // 지킬 연속이 없으면 쓰지 않는다
        guard let firstMissed = missed.first,
              let dayBefore = calendar.date(byAdding: .day, value: -1, to: firstMissed),
              streak(endingAt: dayBefore) > 0 else { return 0 }

        var used = 0
        for day in missed where honeypots > 0 {
            honeypotSavedDays.insert(key(day))
            honeypots -= 1
            lastHoneypotUse = key(day)
            used += 1
        }
        return used
    }

    // MARK: - 쉬어가기

    mutating func startRest(_ reason: RestPeriod.Reason, days: Int, from now: Date = .now) {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: max(days, 1) - 1, to: start) ?? start
        rest = RestPeriod(reason: reason, start: start, end: end)
    }

    mutating func endRest(now: Date = .now) {
        guard let rest = rest else { return }
        // 오늘부터 다시 기록한다: 쉬어간 기간은 어제까지만 남긴다
        let today = calendar.startOfDay(for: now)
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), yesterday >= rest.start {
            self.rest = RestPeriod(reason: rest.reason, start: rest.start, end: yesterday)
        } else {
            self.rest = nil
        }
    }

    // MARK: - 이번 주 벌집

    /// day가 있는 주(월~일)의 칸. 오늘이고 아직 안 했으면 .today
    func weekStates(containing day: Date, today: Date = .now) -> [HoneyCellState] {
        let weekday = calendar.component(.weekday, from: day) // 1=일 … 7=토
        let mondayOffset = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -mondayOffset, to: calendar.startOfDay(for: day)) else {
            return Array(repeating: .empty, count: 7)
        }
        return (0..<7).map { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: monday) else { return .empty }
            if recordOnlyDays.contains(key(date)) { return .recordOnly }
            if isClosed(date) { return .done }
            if isSavedByHoneypot(date) { return .savedByHoneypot }
            if isRest(date) { return .rest }
            if calendar.isDate(date, inSameDayAs: today) { return .today }
            return .empty
        }
    }

}
