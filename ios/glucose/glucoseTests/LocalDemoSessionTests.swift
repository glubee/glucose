import XCTest
@testable import glucose

@MainActor
final class LocalDemoSessionTests: XCTestCase {
    func testActivationPersistsAndDeactivationRestoresNormalMode() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let session = LocalDemoSession(defaults: defaults)
        XCTAssertFalse(session.isActive)
        let initial = session.generation
        session.activate()
        XCTAssertTrue(session.isActive)
        XCTAssertNotEqual(session.generation, initial)
        let restored = LocalDemoSession(defaults: defaults)
        XCTAssertTrue(restored.isActive)
        restored.deactivate()
        XCTAssertFalse(LocalDemoSession(defaults: defaults).isActive)
    }

    func testActivationDoesNotModifyExistingPreferencesAndOnlyExplicitResetRegenerates() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(Data([1,2,3]), forKey: "day_close_v2")
        defaults.set("keep", forKey: "user_preferences_v1")
        let session = LocalDemoSession(defaults: defaults)
        session.activate()
        let generation = session.generation
        session.activate()
        XCTAssertEqual(session.generation, generation)
        session.activate(reset: true)
        XCTAssertNotEqual(session.generation, generation)
        XCTAssertEqual(defaults.data(forKey: "day_close_v2"), Data([1,2,3]))
        XCTAssertEqual(defaults.string(forKey: "user_preferences_v1"), "keep")
    }

    func testLateServerDemoCannotReplaceProgressAfterSessionChanges() async {
        let store = DayCloseStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let original = ReportDay.date(fromAPIString: "2026-10-01")!
        store.markClosed(original)
        var valid = true, widgetWrites = 0
        var continuation: CheckedContinuation<Double?, Never>?
        let work = Task { await DemoDayCloseSync.run(days: 1, store: store,
            fetchCoverage: { _ in await withCheckedContinuation { continuation = $0 } },
            canCommit: { valid }, onSaved: { widgetWrites += 1 }) }
        while continuation == nil { await Task.yield() }
        valid = false
        continuation?.resume(returning: 1)
        let count = await work.value
        XCTAssertEqual(count, 0)
        XCTAssertEqual(store.closedDays, ["2026-10-01"])
        XCTAssertEqual(widgetWrites, 0)
    }

    func testInvalidServerDemoDoesNotStartFetchingOrClearProgress() async {
        let store = DayCloseStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.markClosed(ReportDay.date(fromAPIString: "2026-10-01")!)
        var reads = 0
        _ = await DemoDayCloseSync.run(days: 1, store: store, fetchCoverage: { _ in reads += 1; return nil },
                                      canCommit: { false }, onSaved: {})
        XCTAssertEqual(reads, 0)
        XCTAssertTrue(store.isClosed(ReportDay.date(fromAPIString: "2026-10-01")!))
    }
}
