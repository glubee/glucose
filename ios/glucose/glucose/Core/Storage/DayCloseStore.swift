//
//  DayCloseStore.swift
//  glucose
//
//  하루 마무리와 연속 완성일(docs/ios-design-v4.md 0-1장).
//  - 완성한 날: 하루 마무리를 끝낸 날(그래프가 짧아 "기록만 저장"한 날도 포함, 2026-10-27 Dave 결정)
//  - 꿀단지: 7일 연속마다 1개(최대 2개). 유예가 지난 빠진 날에 자동으로 써서 연속을 지킨다(숫자는 늘지 않음)
//  - 쉬어가기: 그 기간엔 연속이 끊기지도 늘지도 않고, 하루 마무리 알림도 보내지 않는다
//  지금은 기기에만 두고, 서버 day_close 테이블이 생기면 옮긴다(5장 B단계).
//

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

@Observable
final class DayCloseStore {

    static let shared = DayCloseStore()

    /// 어제 마무리는 다음 날 이 시각(정오)까지 인정한다. 리브레 하루 그래프는 자정이 지나야 다 차기 때문
    static let graceHour = 12
    static let maxHoneypots = 2
    static let daysPerHoneypot = 7

    private struct Stored: Codable {
        var closedDays: Set<String> = []
        var recordOnlyDays: Set<String> = []
        var honeypotSavedDays: Set<String> = []
        var honeypots = 0
        var rest: RestPeriod?
        /// 가장 최근에 꿀단지로 지킨 날(알림·홈 안내용)
        var lastHoneypotUse: String?
        /// 하루 마무리 "오늘에 남길 한마디"(날짜 → 글). 기기에만 둔다. 예전 저장값엔 없다
        var notes: [String: String]?
    }

    private var stored: Stored {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private let key = "day_close_v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode(Stored.self, from: data) {
            stored = decoded
        } else {
            stored = Stored()
        }
    }

    var closedDays: Set<String> { stored.closedDays }
    var recordOnlyDays: Set<String> { stored.recordOnlyDays }
    var honeypots: Int { stored.honeypots }
    var rest: RestPeriod? { stored.rest }
    var lastHoneypotUse: String? { stored.lastHoneypotUse }

    private var calendar: Calendar { ReportDay.calendar }
    private func key(_ day: Date) -> String { ReportDay.apiString(from: day) }

    // MARK: - 하루 상태

    func isClosed(_ day: Date) -> Bool { stored.closedDays.contains(key(day)) }

    /// 하루 마무리 한마디(선택). 서버로 보내지 않는다
    func note(for day: Date) -> String { stored.notes?[key(day)] ?? "" }

    func setNote(_ text: String, for day: Date) {
        var notes = stored.notes ?? [:]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        notes[key(day)] = trimmed.isEmpty ? nil : trimmed
        stored.notes = notes
    }
    func isSavedByHoneypot(_ day: Date) -> Bool { stored.honeypotSavedDays.contains(key(day)) }

    func isRest(_ day: Date) -> Bool {
        guard let rest = stored.rest else { return false }
        let d = calendar.startOfDay(for: day)
        return d >= calendar.startOfDay(for: rest.start) && d <= calendar.startOfDay(for: rest.end)
    }

    func isResting(now: Date = .now) -> Bool { isRest(now) }

    func markClosed(_ day: Date, recordOnly: Bool = false) {
        let dayKey = key(day)
        stored.closedDays.insert(dayKey)
        stored.honeypotSavedDays.remove(dayKey)
        if recordOnly { stored.recordOnlyDays.insert(dayKey) }
        // 7일 연속마다 꿀단지 1개
        let streak = streak(endingAt: day)
        if streak > 0, streak % Self.daysPerHoneypot == 0 {
            stored.honeypots = min(Self.maxHoneypots, stored.honeypots + 1)
        }
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
        guard calendar.component(.hour, from: now) < Self.graceHour,
              let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              !isClosed(yesterday), !isRest(yesterday) else {
            return today
        }
        return yesterday
    }

    /// 유예가 지난 빠진 날에 꿀단지를 쓴다. 앱이 열릴 때마다 부른다. 쓴 날 수를 돌려준다
    @discardableResult
    func applyHoneypots(now: Date = .now) -> Int {
        guard stored.honeypots > 0 else { return 0 }
        // 이미 마감된 마지막 날: 유예 중이면 그저께, 아니면 어제
        let today = calendar.startOfDay(for: now)
        let inGrace = calendar.component(.hour, from: now) < Self.graceHour
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
        for day in missed where stored.honeypots > 0 {
            stored.honeypotSavedDays.insert(key(day))
            stored.honeypots -= 1
            stored.lastHoneypotUse = key(day)
            used += 1
        }
        return used
    }

    // MARK: - 쉬어가기

    func startRest(_ reason: RestPeriod.Reason, days: Int, from now: Date = .now) {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: max(days, 1) - 1, to: start) ?? start
        stored.rest = RestPeriod(reason: reason, start: start, end: end)
    }

    func endRest(now: Date = .now) {
        guard let rest = stored.rest else { return }
        // 오늘부터 다시 기록한다: 쉬어간 기간은 어제까지만 남긴다
        let today = calendar.startOfDay(for: now)
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), yesterday >= rest.start {
            stored.rest = RestPeriod(reason: rest.reason, start: rest.start, end: yesterday)
        } else {
            stored.rest = nil
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
            if stored.recordOnlyDays.contains(key(date)) { return .recordOnly }
            if isClosed(date) { return .done }
            if isSavedByHoneypot(date) { return .savedByHoneypot }
            if isRest(date) { return .rest }
            if calendar.isDate(date, inSameDayAs: today) { return .today }
            return .empty
        }
    }

    /// 계정을 지웠을 때
    func reset() {
        stored = Stored()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: key)
    }
}
