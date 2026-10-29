import Foundation

struct ProgressOperation: Codable, Equatable {
    var id = UUID()
    var kind: String
    var day: String?
    var recordOnly: Bool?
    var reason: String?
    var end: String?

    func apply(to state: inout DayCloseState, now: Date = .now) {
        switch kind {
        case "close_day":
            if let day, let date = ReportDay.date(fromAPIString: day) { state.markClosed(date, recordOnly: recordOnly == true) }
        case "start_rest":
            if let day, let end, let reason, let parsed = RestPeriod.Reason(rawValue: reason),
               let first = ReportDay.date(fromAPIString: day), let last = ReportDay.date(fromAPIString: end) {
                state.rest = RestPeriod(reason: parsed, start: first, end: last)
            }
        case "end_rest": if let day, let date = ReportDay.date(fromAPIString: day) { state.endRest(now: date) }
        case "apply_honeypots": state.applyHoneypots(now: now)
        default: break
        }
    }
}

struct RemoteProgressState: Codable, Equatable {
    struct Rest: Codable, Equatable { let reason: String; let start: String; let end: String }
    var closedDays: Set<String> = []
    var recordOnlyDays: Set<String> = []
    var honeypotSavedDays: Set<String> = []
    var honeypots = 0
    var rest: Rest?
    var lastHoneypotUse: String?

    init(_ state: DayCloseState = DayCloseState()) {
        closedDays = state.closedDays; recordOnlyDays = state.recordOnlyDays
        honeypotSavedDays = state.honeypotSavedDays; honeypots = state.honeypots
        lastHoneypotUse = state.lastHoneypotUse
        rest = state.rest.map { Rest(reason: $0.reason.rawValue, start: ReportDay.apiString(from: $0.start), end: ReportDay.apiString(from: $0.end)) }
    }

    func local() throws -> DayCloseState {
        let dates = closedDays.union(recordOnlyDays).union(honeypotSavedDays).union(lastHoneypotUse.map { [$0] } ?? [])
        guard (0...2).contains(honeypots), recordOnlyDays.isSubset(of: closedDays),
              closedDays.isDisjoint(with: honeypotSavedDays), dates.allSatisfy({ value in
                  guard let date = ReportDay.date(fromAPIString: value) else { return false }
                  return ReportDay.apiString(from: date) == value
              }) else { throw APIError.invalidResponse }
        var state = DayCloseState(closedDays: closedDays, recordOnlyDays: recordOnlyDays,
                                  honeypotSavedDays: honeypotSavedDays, honeypots: honeypots, lastHoneypotUse: lastHoneypotUse)
        if let rest {
            guard let reason = RestPeriod.Reason(rawValue: rest.reason),
                  let start = ReportDay.date(fromAPIString: rest.start), let end = ReportDay.date(fromAPIString: rest.end), end >= start
            else { throw APIError.invalidResponse }
            state.rest = RestPeriod(reason: reason, start: start, end: end)
        }
        return state
    }
}

struct ProgressSyncRequest: Encodable {
    var legacyState: RemoteProgressState?
    var operations: [ProgressOperation]
}
struct ProgressSyncResponse: Decodable {
    let revision: Int64
    let state: RemoteProgressState
    let acknowledgedOperations: [UUID]
}
