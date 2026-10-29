import XCTest

/// 하루 그래프(DayChartExplorer): 그래프가 리포트 맨 위, 확대 칩, 그래프 밖 선택 표시, 시각순 기록 목록.
@MainActor
final class ChartInteractionUITests: XCTestCase {
    private func reports() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tabs", "-reportSample"]
        app.launch()
        app.tabBars.buttons["리포트"].tap()
        XCTAssertTrue(app.staticTexts["하루 흐름"].waitForExistence(timeout: 8))
        return app
    }

    func testReportShowsChartBeforeStory() {
        let app = reports()
        let chart = app.staticTexts["하루 흐름"]
        let story = app.staticTexts["하루 이야기"]
        XCTAssertTrue(story.exists)
        XCTAssertLessThan(chart.frame.minY, story.frame.minY)
        XCTAssertTrue(app.buttons["chartZoom-24"].exists)
    }

    func testReportScrollsBothWaysWithoutLosingTabControls() {
        let app = reports()
        let heading = app.staticTexts["하루 흐름"]
        let initialY = heading.frame.minY
        app.swipeUp()
        XCTAssertLessThan(heading.frame.minY, initialY - 80)
        // 같은 횟수의 flick은 감속/속도에 따라 같은 거리로 돌아오지 않는다.
        for _ in 0..<3 where heading.frame.minY < initialY - 5 { app.swipeDown() }
        XCTAssertEqual(heading.frame.minY, initialY, accuracy: 5)
        XCTAssertTrue(app.tabBars.buttons["홈"].isHittable)
    }

    func testZoomShowsRangeAndDayHidesIt() {
        let app = reports()
        app.buttons["chartZoom-3"].tap()
        let range = app.staticTexts["chartVisibleRange"]
        XCTAssertTrue(range.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chartZoom-3"].isSelected)
        app.buttons["chartZoom-24"].tap()
        XCTAssertFalse(range.waitForExistence(timeout: 1))
    }

    func testRecordInListSelectsTimeOutsideChart() {
        let app = reports()
        let strip = app.descendants(matching: .any)["chartSelectionStrip"].firstMatch
        XCTAssertTrue(strip.exists)
        let record = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "식사")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        for _ in 0..<4 where !record.isHittable { app.swipeUp() }
        record.tap()
        let clear = app.buttons["선택 해제"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["앞뒤 45분 안의 기록"].exists)
        for _ in 0..<4 where !clear.isHittable { app.swipeDown() }
        clear.tap()
        XCTAssertFalse(clear.waitForExistence(timeout: 1))
    }

    func testReportScrollsWhenDraggingVerticallyOnChart() {
        let app = reports()
        let content = app.scrollViews["dailyReportContent"]
        let zoom = content.buttons["chartZoom-3"]
        XCTAssertTrue(zoom.isHittable)
        let before = zoom.frame.minY
        let plot = content.descendants(matching: .any)["interactiveChartPlot"].firstMatch
        let start = plot.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.6))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -180)))
        XCTAssertLessThan(zoom.frame.minY, before - 60)
    }

    func testTappingChartShowsValueAboveIt() {
        let app = reports()
        let plot = app.descendants(matching: .any)["interactiveChartPlot"].firstMatch
        plot.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()
        XCTAssertTrue(app.buttons["선택 해제"].waitForExistence(timeout: 5))
    }

    func testHomeChartOpensLargeView() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tabs", "-reportSample"]
        app.launch()
        let chart = app.descendants(matching: .any)["homeTodayChart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 8))
        chart.tap()
        XCTAssertTrue(app.buttons["chartZoom-6"].waitForExistence(timeout: 5))
        app.buttons["closeChartDetail"].tap()
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
    }
}
