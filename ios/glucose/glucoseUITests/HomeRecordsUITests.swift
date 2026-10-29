import XCTest

@MainActor
final class HomeRecordsUITests: XCTestCase {
    private func capture(_ title: String, app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = title
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
    private func launch(empty: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tabs", "-reportSample", empty ? "-timelineEmptySample" : "-timelineSample"]
        app.launch()
        return app
    }

    func testRecordTabFiltersAndReturnsFromSharedDetail() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["기록"].waitForExistence(timeout: 5))
        app.tabBars.buttons["기록"].tap()
        app.buttons["recordFilter-response"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "포도당 캔디")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "현미밥")).firstMatch.exists)
        app.buttons["recordFilter-insulin"].tap()
        let insulin = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "recordRow-insulin-")).firstMatch
        XCTAssertTrue(insulin.waitForExistence(timeout: 5))
        insulin.tap()
        XCTAssertTrue(app.buttons["기록 고치기"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["recordFilter-food"].exists)
        XCTAssertFalse(app.buttons["닫기"].exists)
        app.buttons["recordFilter-all"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "recordRow-intake-")).firstMatch.waitForExistence(timeout: 5))
        capture("records-tab", app: app)
    }

    func testHomePendingPhotoOpensAndCancelsBackToTimeline() {
        let app = launch()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "timeline-pending-")).firstMatch
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.isHittable)
        capture("home-timeline", app: app)
        row.tap()
        XCTAssertTrue(app.buttons["취소"].waitForExistence(timeout: 5))
        app.buttons["취소"].tap()
        XCTAssertTrue(app.tabBars.buttons["홈"].waitForExistence(timeout: 5))
        XCTAssertTrue(row.isHittable)
    }

    func testEmptyHomeCanSaveTextThenRevealTheNewRowAndFindItInRecordTab() {
        let app = launch(empty: true)
        app.buttons["음식 찍기"].tap()
        let write = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "글로 남기기")).firstMatch
        XCTAssertTrue(write.waitForExistence(timeout: 5))
        write.tap()
        let name = app.textFields["음식 이름"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("새 기록\n")
        app.buttons["기록 남기기"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "timeline-intake-", "새 기록")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isHittable)
        app.tabBars.buttons["기록"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "새 기록")).firstMatch.waitForExistence(timeout: 5))
    }

    func testFoodEditAndDeleteRefreshBothScreens() {
        let app = launch()
        app.tabBars.buttons["기록"].tap()
        app.buttons["recordFilter-food"].tap()
        let original = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "현미밥")).firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 5))
        original.tap()
        app.buttons["기록 고치기"].tap()
        let name = app.textFields["음식 이름"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        if let text = name.value as? String { name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count)) }
        name.typeText("수정한 밥\n")
        app.buttons["변경 저장하기"].tap()
        let changed = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "수정한 밥")).firstMatch
        XCTAssertTrue(changed.waitForExistence(timeout: 5))
        changed.tap()
        app.buttons["기록 고치기"].tap()
        let delete = app.buttons["이 기록 지우기"]
        for _ in 0..<3 where !delete.isHittable { app.swipeUp() }
        delete.tap()
        app.buttons["기록 지우기"].tap()
        XCTAssertTrue(app.buttons["recordFilter-food"].waitForExistence(timeout: 5))
        XCTAssertFalse(changed.exists)
        app.tabBars.buttons["홈"].tap()
        for _ in 0..<5 { app.swipeUp() }
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "수정한 밥")).firstMatch.exists)
    }

    func testCreatedRecordScrollsPastExistingTimelineAndIsHighlighted() {
        let app = launch()
        app.buttons["음식 찍기"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "글로 남기기")).firstMatch.tap()
        let name = app.textFields["음식 이름"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("방금 남긴 음식\n")
        app.buttons["기록 남기기"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "timeline-intake-", "방금 남긴 음식")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isHittable)
        XCTAssertEqual(row.value as? String, "새로 추가한 기록")
    }
}
