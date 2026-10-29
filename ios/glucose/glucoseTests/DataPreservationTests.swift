import XCTest
@testable import glucose

@MainActor
final class DataPreservationTests: XCTestCase {
    private func store() -> DayCloseStore { DayCloseStore(defaults: UserDefaults(suiteName: UUID().uuidString)!) }
    private func day(_ n: Int) -> Date { ReportDay.date(fromAPIString: "2026-10-\(String(format: "%02d", n))")! }

    func testDuplicateSeventhDayDoesNotAwardTwice() {
        let store = store()
        for n in 1...7 { store.markClosed(day(n)) }
        store.markClosed(day(7))
        XCTAssertEqual(store.honeypots, 1)
    }

    func testOutOfOrderSeventhDayEarnsReward() {
        let store = store()
        for n in 2...7 { store.markClosed(day(n)) }
        store.markClosed(day(1))
        XCTAssertEqual(store.honeypots, 1)
    }

    func testFullCompletionUpgradesRecordOnlyAndCannotDowngrade() {
        let store = store()
        store.markClosed(day(1), recordOnly: true)
        store.markClosed(day(1))
        store.markClosed(day(1), recordOnly: true)
        XCTAssertFalse(store.recordOnlyDays.contains("2026-10-01"))
    }

    func testQueueSurvivesRestartAndResponseReplaysNewWork() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let first = DayCloseStore(defaults: defaults)
        first.markClosed(day(1))
        let restarted = DayCloseStore(defaults: defaults)
        let sent = restarted.makeSyncRequest()
        XCTAssertEqual(sent.operations.count, 1)
        restarted.markClosed(day(2))
        var canonical = DayCloseState(); canonical.markClosed(day(1))
        try restarted.applyServer(ProgressSyncResponse(revision: 4, state: RemoteProgressState(canonical), acknowledgedOperations: sent.operations.map(\.id)), for: sent)
        XCTAssertEqual(restarted.closedDays, ["2026-10-01", "2026-10-02"])
        XCTAssertEqual(restarted.makeSyncRequest().operations.count, 1)
        try restarted.applyServer(ProgressSyncResponse(revision: 3, state: RemoteProgressState(), acknowledgedOperations: []), for: sent)
        XCTAssertTrue(restarted.isClosed(day(1)))
    }

    func testAccountSwitchHidesAndRestoresOwnedStateAndQueue() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = DayCloseStore(defaults: defaults, accountScoped: true)
        let a = UUID(), b = UUID()
        store.activateAccount(a); store.markClosed(day(1))
        store.activateAccount(b)
        XCTAssertTrue(store.closedDays.isEmpty)
        XCTAssertTrue(store.makeSyncRequest().operations.isEmpty)
        store.markClosed(day(2)); store.activateAccount(nil)
        XCTAssertTrue(store.closedDays.isEmpty)
        store.activateAccount(a)
        XCTAssertEqual(store.closedDays, ["2026-10-01"])
        XCTAssertEqual(store.makeSyncRequest().operations.count, 1)
    }

    func testUnattributedLegacyIsQuarantinedAndClaimedOnlyOnce() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        DayCloseStore(defaults: defaults).markClosed(day(1))
        let store = DayCloseStore(defaults: defaults, accountScoped: true)
        store.activateAccount(UUID())
        XCTAssertTrue(store.closedDays.isEmpty)
        XCTAssertTrue(store.hasUnclaimedLegacy)
        XCTAssertTrue(store.claimLegacyForActiveAccount())
        XCTAssertTrue(store.isClosed(day(1)))
        XCTAssertNotNil(store.makeSyncRequest().legacyState)
        store.markClosed(day(2))
        XCTAssertEqual(store.makeSyncRequest().legacyState?.closedDays, ["2026-10-01"])
        store.activateAccount(UUID(), allowLegacy: true)
        XCTAssertTrue(store.closedDays.isEmpty)
        XCTAssertFalse(store.hasUnclaimedLegacy)
    }

    func testKnownOwnerMigrationAndPreferencesDoNotReachNextAccount() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let legacy = UserPreferences(defaults: defaults)
        legacy.nickname = "예시"; legacy.usualInsulins = [UsualInsulin(name: "사용자 입력", units: 4)]
        legacy.onboardingCompleted = true
        let preferences = UserPreferences(defaults: defaults, accountScoped: true)
        let a = UUID(), b = UUID()
        preferences.activateAccount(a, allowLegacy: true)
        XCTAssertEqual(preferences.usualInsulins.count, 1)
        preferences.activateAccount(nil)
        XCTAssertTrue(preferences.nickname.isEmpty)
        XCTAssertTrue(preferences.onboardingCompleted)
        preferences.activateAccount(b, allowLegacy: true)
        XCTAssertTrue(preferences.usualInsulins.isEmpty)
        preferences.activateAccount(a)
        XCTAssertEqual(preferences.nickname, "예시")
    }

    func testMalformedResponseCannotDropPendingOperation() throws {
        let store = store(); store.markClosed(day(1))
        let request = store.makeSyncRequest()
        var invalid = RemoteProgressState(); invalid.honeypots = -1
        XCTAssertThrowsError(try store.applyServer(ProgressSyncResponse(revision: 1, state: invalid, acknowledgedOperations: request.operations.map(\.id)), for: request))
        XCTAssertTrue(store.hasPendingChanges)
        XCTAssertTrue(store.isClosed(day(1)))
    }

    func testJWTSubjectIsUsedOnlyWhenItIsAUUID() throws {
        let id = UUID()
        let payload = try JSONSerialization.data(withJSONObject: ["sub": id.uuidString])
            .base64EncodedString().replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(AccountIdentity.userID(in: "header.\(payload).signature"), id)
        XCTAssertNil(AccountIdentity.userID(in: "malformed"))
    }

    func testLegacyImportCannotDowngradeAnAlreadyFullCompletion() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        DayCloseStore(defaults: defaults).markClosed(day(1), recordOnly: true)
        let store = DayCloseStore(defaults: defaults, accountScoped: true)
        store.activateAccount(UUID()); store.markClosed(day(1))
        let request = store.makeSyncRequest()
        var canonical = DayCloseState(); canonical.markClosed(day(1))
        try store.applyServer(ProgressSyncResponse(revision: 1, state: RemoteProgressState(canonical), acknowledgedOperations: request.operations.map(\.id)), for: request)
        XCTAssertTrue(store.claimLegacyForActiveAccount())
        XCTAssertFalse(store.recordOnlyDays.contains("2026-10-01"))
    }

    func testDeletingAnAccountAlsoErasesItsClaimedLegacyPreferencesAndProgress() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!, id = UUID()
        DayCloseStore(defaults: defaults).markClosed(day(1))
        let original = UserPreferences(defaults: defaults); original.nickname = "예시 사용자"
        let progress = DayCloseStore(defaults: defaults, accountScoped: true)
        let prefs = UserPreferences(defaults: defaults, accountScoped: true)
        progress.activateAccount(id, allowLegacy: true); prefs.activateAccount(id, allowLegacy: true)
        progress.eraseActiveAccount(); prefs.eraseActiveAccount()
        XCTAssertNil(defaults.data(forKey: "day_close_v2"))
        XCTAssertNil(defaults.data(forKey: "user_preferences_v1"))
        XCTAssertNil(defaults.data(forKey: "day_close_v3.\(id.uuidString)"))
        XCTAssertNil(defaults.data(forKey: "user_preferences_v2.\(id.uuidString)"))
    }
}
