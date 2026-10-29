import XCTest
import Vision

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

    func testDailyChartEventOpensPopupBeforeExplicitPhotoView() throws {
        let app = launch()
        let event = app.scrollViews["dailyReportContent"].buttons["chartEvent-insulin-0"]
        XCTAssertTrue(event.waitForExistence(timeout: 8))
        reveal(event, in: app)
        event.tap()
        XCTAssertTrue(app.staticTexts["이 시각의 기록"].waitForExistence(timeout: 5))
        let screenshot = app.screenshot()
        let popup = XCTAttachment(screenshot: screenshot)
        popup.name = "Inline event popup"
        popup.lifetime = .keepAlways
        add(popup)
        let recognition = VNRecognizeTextRequest()
        recognition.recognitionLanguages = ["ko-KR"]
        recognition.recognitionLevel = .accurate
        try VNImageRequestHandler(data: screenshot.pngRepresentation).perform([recognition])
        let titleVisible = (recognition.results ?? []).contains {
            $0.topCandidates(1).first?.string.replacingOccurrences(of: " ", with: "").contains("이시각의기록") == true
        }
        XCTAssertTrue(titleVisible, "팝업 제목은 접근성 트리뿐 아니라 실제 화면에서도 보여야 한다")
        app.buttons["popupEvent-intake-0"].tap()
        app.buttons["사진 크게 보기"].tap()
        XCTAssertTrue(app.navigationBars["사진 기록"].waitForExistence(timeout: 5))
        app.buttons["closePhotoGallery"].tap()
        app.buttons["closeChartEventPopup"].tap()
        XCTAssertTrue(app.buttons["chartZoom-24"].exists)
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
        XCTAssertTrue(app.buttons["detailChartZoom-3"].waitForExistence(timeout: 8))
        let initialPhoto = app.buttons["chartPhoto-08:10"]
        XCTAssertTrue(initialPhoto.waitForExistence(timeout: 5))
        let originalX = initialPhoto.frame.midX
        app.buttons["detailChartZoom-3"].tap()
        let photo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chartPhoto-")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.tap()
        XCTAssertTrue(app.navigationBars["사진 기록"].waitForExistence(timeout: 5))
        app.buttons["closePhotoGallery"].tap()
        XCTAssertTrue(app.buttons["detailChartZoom-24"].waitForExistence(timeout: 5))
        app.buttons["detailChartZoom-24"].tap()
        XCTAssertTrue(initialPhoto.waitForExistence(timeout: 5))
        XCTAssertEqual(initialPhoto.frame.midX, originalX, accuracy: 2)
        app.buttons["closeChartDetail"].tap()
        XCTAssertTrue(app.buttons["음식 찍기"].waitForExistence(timeout: 5))
    }
}
