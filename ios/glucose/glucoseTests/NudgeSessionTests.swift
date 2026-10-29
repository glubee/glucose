import XCTest
import UserNotifications
@testable import glucose

@MainActor
final class NudgeSessionTests: XCTestCase {
    func testAccountChangeDuringNotificationAddRemovesTheLateOldRequestAndStopsThePlan() async {
        let prefs = UserPreferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let progress = DayCloseStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let center = PausedNudgeNotifications()
        var current = true
        let work = Task { await NudgeScheduler.refresh(preferences: prefs, store: progress,
            now: ReportDay.date(fromAPIString: "2026-10-20")!, notifications: center, isCurrent: { current }) }
        while center.continuation == nil { await Task.yield() }
        current = false
        center.requests.removeAll() // Account switch/deletion clears pending notifications.
        center.continuation?.resume()
        await work.value
        XCTAssertTrue(center.requests.isEmpty)
        XCTAssertEqual(center.attempts, 1)
    }
    func testLateOldAddCannotEraseTheNewAccountsNotifications() async {
        let prefs = UserPreferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let progress = DayCloseStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let center = PausedNudgeNotifications(), now = ReportDay.date(fromAPIString: "2026-10-20")!
        var current = true
        let old = Task { await NudgeScheduler.refresh(preferences: prefs, store: progress,
            now: now, notifications: center, isCurrent: { current }) }
        while center.continuation == nil { await Task.yield() }
        current = false
        center.requests.removeAll()
        await NudgeScheduler.refresh(preferences: prefs, store: progress, now: now, notifications: center, isCurrent: { true })
        let newIDs = Set(center.requests.map(\.identifier))
        XCTAssertFalse(newIDs.isEmpty)
        center.continuation?.resume()
        await old.value
        XCTAssertEqual(Set(center.requests.map(\.identifier)), newIDs)
        XCTAssertEqual(center.requests.count, newIDs.count)
    }

}

@MainActor
private final class PausedNudgeNotifications: NudgeNotificationServing {
    var requests: [UNNotificationRequest] = []
    var attempts = 0
    var continuation: CheckedContinuation<Void, Never>?
    func pending() async -> [UNNotificationRequest] { requests }
    func isAuthorized() async -> Bool { true }
    func remove(_ identifiers: [String]) { requests.removeAll { identifiers.contains($0.identifier) } }
    func add(_ request: UNNotificationRequest) async throws {
        attempts += 1
        if attempts == 1 { await withCheckedContinuation { continuation = $0 } }
        requests.append(request)
    }
}
