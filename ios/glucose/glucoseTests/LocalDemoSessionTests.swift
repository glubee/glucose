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
}
