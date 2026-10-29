import Foundation

@Observable
final class DayCloseStore {
    static let shared = DayCloseStore(accountScoped: true)
    static let graceHour = 12
    static let maxHoneypots = 2
    static let daysPerHoneypot = 7
    private struct Envelope: Codable {
        var state = DayCloseState()
        var operations: [ProgressOperation] = []
        var revision: Int64 = -1
        var legacy: RemoteProgressState?
        var synced = false
    }
    private var envelope = Envelope()
    private let defaults: UserDefaults
    private let accountScoped: Bool
    private var accountID: UUID?
    private var key: String
    var onMutation: (() -> Void)?
    private var state: DayCloseState { envelope.state }

    init(defaults: UserDefaults = .standard, accountScoped: Bool = false) {
        self.defaults = defaults; self.accountScoped = accountScoped
        key = accountScoped ? "day_close_v3.signed_out" : "day_close_v2"
        load()
    }
    var closedDays: Set<String> { state.closedDays }
    var recordOnlyDays: Set<String> { state.recordOnlyDays }
    var honeypots: Int { state.honeypots }
    var rest: RestPeriod? { state.rest }
    var lastHoneypotUse: String? { state.lastHoneypotUse }
    var hasPendingChanges: Bool { !envelope.operations.isEmpty || envelope.legacy != nil }
    var hasSynced: Bool { envelope.synced }
    var hasUnclaimedLegacy: Bool {
        defaults.string(forKey: "day_close_legacy_owner") == nil && legacyState() != nil
    }
    func isClosed(_ day: Date) -> Bool { state.isClosed(day) }
    func isSavedByHoneypot(_ day: Date) -> Bool { state.isSavedByHoneypot(day) }
    func isRest(_ day: Date) -> Bool { state.isRest(day) }
    func isResting(now: Date = .now) -> Bool { state.isResting(now: now) }
    func streak(endingAt day: Date) -> Int { state.streak(endingAt: day) }
    func targetDay(now: Date = .now) -> Date { state.targetDay(now: now) }
    func weekStates(containing day: Date, today: Date = .now) -> [HoneyCellState] { state.weekStates(containing: day, today: today) }
    func markClosed(_ day: Date, recordOnly: Bool = false) {
        mutate(ProgressOperation(kind: "close_day", day: ReportDay.apiString(from: day), recordOnly: recordOnly))
    }
    @discardableResult func applyHoneypots(now: Date = .now) -> Int {
        var projected = state
        let used = projected.applyHoneypots(now: now)
        if used > 0 { mutate(ProgressOperation(kind: "apply_honeypots"), now: now) }
        return used
    }
    func startRest(_ reason: RestPeriod.Reason, days: Int, from now: Date = .now) {
        let start = ReportDay.calendar.startOfDay(for: now)
        let end = ReportDay.calendar.date(byAdding: .day, value: min(max(days, 1), 366) - 1, to: start)!
        mutate(ProgressOperation(kind: "start_rest", day: ReportDay.apiString(from: start), reason: reason.rawValue, end: ReportDay.apiString(from: end)))
    }
    func endRest(now: Date = .now) {
        guard rest != nil else { return }
        mutate(ProgressOperation(kind: "end_rest", day: ReportDay.apiString(from: now)))
    }
    func eraseActiveAccount() {
        reset()
        guard accountScoped, let accountID else { return }
        defaults.removeObject(forKey: key)
        if defaults.string(forKey: "day_close_legacy_owner") == accountID.uuidString {
            defaults.removeObject(forKey: "day_close_v2")
            defaults.removeObject(forKey: "day_close_legacy_owner")
        }
    }

    func reset() { envelope = Envelope(); save() }

    func activateAccount(_ id: UUID?, allowLegacy: Bool = false) {
        guard accountScoped else { return }
        accountID = id
        key = "day_close_v3.\(id?.uuidString ?? "signed_out")"
        load()
        // Signed-out data is never shown or sent as another account's history.
        if id == nil { envelope = Envelope() }
        if allowLegacy { claimLegacyForActiveAccount() }
    }

    @discardableResult func claimLegacyForActiveAccount() -> Bool {
        guard let accountID, hasUnclaimedLegacy, let legacy = legacyState() else { return false }
        let hasCurrentHistory = !state.closedDays.isEmpty || !state.honeypotSavedDays.isEmpty || state.honeypots > 0 || state.rest != nil
        var imported: DayCloseState
        if envelope.synced && hasCurrentHistory {
            imported = state
        } else {
            imported = legacy
            for operation in envelope.operations { operation.apply(to: &imported) }
        }
        let fullDays = imported.closedDays.subtracting(imported.recordOnlyDays)
            .union(state.closedDays.subtracting(state.recordOnlyDays))
            .union(legacy.closedDays.subtracting(legacy.recordOnlyDays))
        imported.closedDays.formUnion(state.closedDays.union(legacy.closedDays))
        imported.recordOnlyDays.formUnion(state.recordOnlyDays.union(legacy.recordOnlyDays))
        imported.recordOnlyDays.subtract(fullDays)
        imported.honeypotSavedDays.formUnion(state.honeypotSavedDays.union(legacy.honeypotSavedDays))
        imported.honeypotSavedDays.subtract(imported.closedDays)
        envelope.state = imported
        envelope.legacy = RemoteProgressState(legacy) // frozen BEFORE queued edits
        save()
        defaults.set(accountID.uuidString, forKey: "day_close_legacy_owner")
        onMutation?()
        return true
    }
    func makeSyncRequest(maxOperations: Int = 100) -> ProgressSyncRequest {
        ProgressSyncRequest(legacyState: envelope.legacy, operations: Array(envelope.operations.prefix(min(max(maxOperations, 1), 100))))
    }
    func applyServer(_ response: ProgressSyncResponse, for request: ProgressSyncRequest) throws {
        guard response.revision >= envelope.revision else { return }
        var canonical = try response.state.local()
        let sent = Set(request.operations.map(\.id))
        let acknowledged = Set(response.acknowledgedOperations).intersection(sent)
        let remaining = envelope.operations.filter { !acknowledged.contains($0.id) }
        for operation in remaining { operation.apply(to: &canonical) }
        envelope.state = canonical
        envelope.operations = remaining
        envelope.revision = response.revision
        if request.legacyState == envelope.legacy { envelope.legacy = nil }
        envelope.synced = true
        save()
    }
    private func mutate(_ operation: ProgressOperation, now: Date = .now) {
        operation.apply(to: &envelope.state, now: now)
        envelope.operations.append(operation)
        save()
        onMutation?()
    }
    private func load() {
        envelope = Envelope()
        guard let data = defaults.data(forKey: key) else { return }
        if let value = try? JSONDecoder().decode(Envelope.self, from: data) { envelope = value }
        else if !accountScoped, let value = try? JSONDecoder().decode(DayCloseState.self, from: data) {
            envelope.state = value; envelope.legacy = RemoteProgressState(value)
        }
    }
    private func legacyState() -> DayCloseState? {
        guard let data = defaults.data(forKey: "day_close_v2") else { return nil }
        let state = (try? JSONDecoder().decode(Envelope.self, from: data))?.state
            ?? (try? JSONDecoder().decode(DayCloseState.self, from: data))
        guard let state, !state.closedDays.isEmpty || state.rest != nil || state.honeypots > 0 || !state.honeypotSavedDays.isEmpty else { return nil }
        return state
    }
    private func save() { defaults.set(try? JSONEncoder().encode(envelope), forKey: key) }
}
