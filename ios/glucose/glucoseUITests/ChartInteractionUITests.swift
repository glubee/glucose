import XCTest

@MainActor
final class ChartInteractionUITests: XCTestCase {
    private func reports() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tabs", "-reportSample"]
        app.launch()
        app.tabBars.buttons["리포트"].tap()
        XCTAssertTrue(app.staticTexts["하루 이야기"].waitForExistence(timeout: 8))
        return app
    }

    func testReportScrollsWhenDraggingOnStoryText() {
        let app = reports()
        let heading = app.staticTexts["하루 이야기"]
        let initialY = heading.frame.minY
        let story = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "이 날 그래프에서 읽힌 값은")).firstMatch
        XCTAssertTrue(story.exists)
        let start = story.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let end = start.withOffset(CGVector(dx: 0, dy: -220))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertLessThan(heading.frame.minY, initialY - 80)
    }

    func testReportScrollsBothWaysWithoutLosingTabControls() {
        let app = reports()
        let heading = app.staticTexts["하루 이야기"]
        let initialY = heading.frame.minY
        app.swipeUp()
        XCTAssertLessThan(heading.frame.minY, initialY - 80)
        // 같은 횟수의 flick은 감속/속도에 따라 같은 거리로 돌아오지 않는다.
        for _ in 0..<3 where heading.frame.minY < initialY - 5 { app.swipeDown() }
        XCTAssertEqual(heading.frame.minY, initialY, accuracy: 5)
        XCTAssertTrue(app.tabBars.buttons["홈"].isHittable)
    }
    func testHomeHasInlineEventPopupAndZoom() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tabs", "-reportSample"]
        app.launch()
        let zoom = app.buttons["chartZoom-3"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 8))
        for _ in 0..<3 where !zoom.isHittable { app.swipeUp() }
        zoom.tap()
        let marker = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chartEvent-")).firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        marker.tap()
        XCTAssertTrue(app.staticTexts["이 시각의 기록"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["closeChartEventPopup"].exists)
        app.buttons["closeChartEventPopup"].tap()
        XCTAssertTrue(app.buttons["chartZoom-24"].exists)
        XCTAssertFalse(app.navigationBars["사진 기록"].exists)
    }

    func testPopupSelectsExactEventAndInsulinDetailIsReadonly() {
        let app = homeWithChart()
        app.buttons["chartZoom-3"].tap()
        app.buttons["chartEvent-insulin-0"].tap()
        XCTAssertTrue(app.buttons["popupEvent-intake-0"].waitForExistence(timeout: 5))
        app.buttons["popupEvent-intake-0"].tap()
        XCTAssertTrue(app.buttons["popupEvent-intake-0"].isSelected)
        app.buttons["popupEvent-insulin-0"].tap()
        app.buttons["chartEventRecordDetail"].tap()
        XCTAssertTrue(app.buttons["기록 고치기"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["기록 고치기"].isEnabled)
        app.buttons["closeChartRecord"].tap()
        app.buttons["closeChartEventPopup"].tap()
    }

    func testZoomPanAndDayReturnKeepRangeConsistent() {
        let app = homeWithChart()
        app.buttons["chartZoom-3"].tap()
        let range = app.staticTexts["chartVisibleRange"]
        let before = range.label
        app.buttons["다음 시간 보기"].tap()
        XCTAssertNotEqual(range.label, before)
        app.buttons["chartZoom-24"].tap()
        XCTAssertEqual(range.label, "00:00 – 24:00")
    }

    func testPinchZoomWorksInCurrentScreen() {
        let app = homeWithChart()
        let plot = app.otherElements["interactiveChartPlot"].firstMatch
        XCTAssertTrue(plot.exists)
        plot.pinch(withScale: 1.8, velocity: 1)
        XCTAssertNotEqual(app.staticTexts["chartVisibleRange"].label, "00:00 – 24:00")
        XCTAssertTrue(app.tabBars.buttons["홈"].exists)
    }

    func testReportScrollsWhenDraggingVerticallyOnChart() {
        let app = reports()
        let content = app.scrollViews["dailyReportContent"]
        let zoom = content.buttons["chartZoom-3"]
        // 빠른 flick은 버튼을 고정 헤더 뒤까지 건너뛸 수 있다. 위치를 맞춘 후 차트 위 드래그를 검사한다.
        let targetY = content.frame.minY + 80
        for _ in 0..<8 {
            if zoom.isHittable && abs(zoom.frame.minY - targetY) < 50 { break }
            let shift = max(-180, min(180, targetY - zoom.frame.minY))
            let point = content.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            point.press(forDuration: 0.05, thenDragTo: point.withOffset(CGVector(dx: 0, dy: shift)))
        }
        XCTAssertTrue(zoom.isHittable)
        let before = zoom.frame.minY
        let plot = content.otherElements["interactiveChartPlot"].firstMatch
        let start = plot.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -180)))
        XCTAssertLessThan(zoom.frame.minY, before - 60)
    }

    func testNarrowingZoomPreservesEveningViewport() {
        let app = homeWithChart()
        app.buttons["chartZoom-6"].tap()
        for _ in 0..<4 { app.buttons["다음 시간 보기"].tap() }
        XCTAssertEqual(app.staticTexts["chartVisibleRange"].label, "17:00 – 23:00")
        app.buttons["chartZoom-3"].tap()
        XCTAssertEqual(app.staticTexts["chartVisibleRange"].label, "18:30 – 21:30")
    }

    func testZoomKeepsPreviouslySelectedEveningEventInFocus() {
        let app = homeWithChart()
        let markers = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chartEvent-"))
        let last = markers.allElementsBoundByIndex.last!
        for _ in 0..<3 where !last.isHittable { app.swipeUp() }
        last.tap()
        let evening = app.buttons["popupEvent-intake-5"]
        XCTAssertTrue(evening.waitForExistence(timeout: 5))
        evening.tap()
        app.buttons["closeChartEventPopup"].tap()
        app.buttons["chartZoom-3"].tap()
        XCTAssertEqual(app.staticTexts["chartVisibleRange"].label, "17:30 – 20:30")
    }

    private func homeWithChart() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tabs", "-reportSample"]
        app.launch()
        let zoom = app.buttons["chartZoom-3"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 8))
        for _ in 0..<4 where !zoom.isHittable { app.swipeUp() }
        XCTAssertTrue(zoom.isHittable)
        return app
    }

}
