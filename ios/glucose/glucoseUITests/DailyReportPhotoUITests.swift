import XCTest

@MainActor
final class DailyReportPhotoUITests: XCTestCase {
    private func launch(_ argument: String = "-dailyReportPreview", extraArguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [argument] + extraArguments
        app.launch()
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    func testStoryAppearsBeforeNumbersAndPreviewCanClose() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["하루 이야기"].waitForExistence(timeout: 8))
        XCTAssertLessThan(app.staticTexts["하루 이야기"].frame.minY, app.staticTexts["평균 혈당"].frame.minY)
        app.buttons["closeDailyReportPreview"].tap()
        XCTAssertTrue(app.buttons["음식 찍기"].waitForExistence(timeout: 5))
    }

    func testGroupedPhotosOpenIndividualReadonlyRecords() {
        let app = launch()
        let photo = app.buttons["photoTimeline-08:10"]
        XCTAssertTrue(photo.waitForExistence(timeout: 8))
        reveal(photo, in: app)
        photo.tap()
        XCTAssertTrue(app.navigationBars["사진 기록"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["사진 3장"].exists)
        app.buttons["사진 더 크게 보기"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["음식 사진"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let detail = app.buttons["photoRecordDetail-0"]
        reveal(detail, in: app)
        detail.tap()
        XCTAssertTrue(app.buttons["기록 고치기"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["기록 고치기"].isEnabled)
        XCTAssertTrue(app.staticTexts["현미밥"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["사진 기록"].waitForExistence(timeout: 5))
        app.buttons["closePhotoGallery"].tap()
        XCTAssertTrue(app.buttons["photoTimeline-08:10"].waitForExistence(timeout: 5))
    }

    func testPhotosRemainAccessibleWhenGraphRequiresReprocessing() {
        let app = launch(extraArguments: ["-reportReprocessSample"])
        XCTAssertTrue(app.staticTexts["그래프를 다시 읽어야 해요"].waitForExistence(timeout: 8))
        let photo = app.buttons["photoTimeline-08:10"]
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        reveal(photo, in: app)
        photo.tap()
        XCTAssertTrue(app.navigationBars["사진 기록"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["사진 3장"].exists)
    }

    func testDailyChartPhotoIsDistinctFromSelectedValue() {
        let app = launch()
        XCTAssertTrue(app.buttons["chartZoom-24"].waitForExistence(timeout: 8))
        let record = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "08:10")).firstMatch
        reveal(record, in: app)
        record.tap()
        // 고른 시각의 혈당은 그래프 위 사진과 겹치지 않게 그래프 밖 줄에 나온다.
        XCTAssertTrue(app.buttons["선택 해제"].waitForExistence(timeout: 5))
        let photo = app.buttons["photoTimeline-08:10"]
        reveal(photo, in: app)
        photo.tap()
        XCTAssertTrue(app.navigationBars["사진 기록"].waitForExistence(timeout: 5))
        app.buttons["closePhotoGallery"].tap()
        XCTAssertTrue(app.buttons["photoTimeline-08:10"].waitForExistence(timeout: 5))
    }

    func testGapPhotoRemainsAvailableBelowChart() {
        let app = launch()
        let photo = app.buttons["photoTimeline-11:00"]
        XCTAssertTrue(photo.waitForExistence(timeout: 8))
        reveal(photo, in: app)
        XCTAssertTrue(photo.label.contains("그래프 비어 있음"))
        photo.tap()
        XCTAssertTrue(app.navigationBars["사진 기록"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["요거트 1개"].exists)
    }

    func testExpandedChartPhotoWorksAfterZoomAndCanClose() {
        let app = launch("-chartDetail")
        XCTAssertTrue(app.buttons["chartZoom-3"].waitForExistence(timeout: 8))
        app.buttons["chartZoom-3"].tap()
        XCTAssertTrue(app.staticTexts["chartVisibleRange"].waitForExistence(timeout: 5))
        let photo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "photoTimeline-")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        reveal(photo, in: app)
        photo.tap()
        XCTAssertTrue(app.navigationBars["사진 기록"].waitForExistence(timeout: 5))
        app.buttons["closePhotoGallery"].tap()
        XCTAssertTrue(app.buttons["chartZoom-24"].waitForExistence(timeout: 5))
        app.buttons["closeChartDetail"].tap()
        XCTAssertTrue(app.buttons["음식 찍기"].waitForExistence(timeout: 5))
    }
}
