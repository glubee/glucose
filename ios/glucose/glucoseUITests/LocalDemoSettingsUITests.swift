import XCTest

@MainActor
final class LocalDemoSettingsUITests: XCTestCase {
    override func tearDown() {
        let app = XCUIApplication()
        if app.tabBars.buttons["설정"].exists { app.tabBars.buttons["설정"].tap() }
        let end = app.buttons["기기 데모 종료"]
        if end.exists {
            for _ in 0..<8 where !end.isHittable { app.swipeUp() }
            if end.isHittable { end.tap() }
        }
        super.tearDown()
    }

    func testSettingsScenarioButtonShowsGraphAndRecordsWithoutLogin() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tabs"]
        app.launch()
        app.tabBars.buttons["설정"].tap()
        let load = app.buttons["시나리오 기록 넣기"]
        for _ in 0..<8 where !load.isHittable { app.swipeUp() }
        XCTAssertTrue(load.isHittable)
        load.tap()
        app.tabBars.buttons["홈"].tap()
        XCTAssertTrue(app.otherElements["interactiveChartPlot"].waitForExistence(timeout: 8))
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "timeline-intake-")).firstMatch
        for _ in 0..<5 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.isHittable)
        XCTAssertTrue(app.staticTexts["예시 기록 · 서버에 저장되지 않아요"].exists)
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "settings-local-demo-home"; capture.lifetime = .keepAlways
        add(capture)
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.staticTexts["localDemoNotice"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.otherElements["interactiveChartPlot"].waitForExistence(timeout: 8))
        app.tabBars.buttons["설정"].tap()
        let end = app.buttons["기기 데모 종료"]
        for _ in 0..<8 where !end.isHittable { app.swipeUp() }
        XCTAssertTrue(end.isHittable)
        end.tap()
        XCTAssertFalse(app.staticTexts["예시 기록 · 서버에 저장되지 않아요"].exists)
        app.terminate()
        app.launchArguments = ["-onboardingStep", "7"]
        app.launch()
        XCTAssertTrue(app.buttons["startLocalDemo"].waitForExistence(timeout: 10))
        app.buttons["startLocalDemo"].tap()
        XCTAssertTrue(app.staticTexts["localDemoNotice"].waitForExistence(timeout: 8))
        app.tabBars.buttons["설정"].tap()
        for _ in 0..<8 where !end.isHittable { app.swipeUp() }
        end.tap()
    }

    func testStandaloneSettingsAndLoginCanEnterLocalDemo() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-settings"]
        app.launch()
        let load = app.buttons["시나리오 기록 넣기"]
        for _ in 0..<8 where !load.isHittable { app.swipeUp() }
        load.tap()
        XCTAssertTrue(app.tabBars.buttons["홈"].waitForExistence(timeout: 8))
        app.tabBars.buttons["설정"].tap()
        let end = app.buttons["기기 데모 종료"]
        for _ in 0..<8 where !end.isHittable { app.swipeUp() }
        end.tap()
        app.terminate()
        app.launchArguments = ["-login"]
        app.launch()
        app.buttons["startLocalDemo"].tap()
        XCTAssertTrue(app.tabBars.buttons["홈"].waitForExistence(timeout: 8))
        app.tabBars.buttons["설정"].tap()
        for _ in 0..<8 where !end.isHittable { app.swipeUp() }
        end.tap()
    }
    func testReportsUseTheLocalDemoCompletionStore() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tabs"]
        app.launch()
        app.tabBars.buttons["설정"].tap()
        let load = app.buttons["시나리오 기록 넣기"]
        for _ in 0..<8 where !load.isHittable { app.swipeUp() }
        load.tap()
        app.tabBars.buttons["설정"].tap()
        let fill = app.buttons["데모 벌집·연속 다시 채우기"]
        for _ in 0..<8 where !fill.isHittable { app.swipeUp() }
        fill.tap()
        app.tabBars.buttons["리포트"].tap()
        app.buttons["이전 날"].tap()
        let note = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "이 날 하루를 완성했어요.")).firstMatch
        for _ in 0..<18 where !note.isHittable { app.swipeUp() }
        XCTAssertTrue(note.isHittable)
    }
}
