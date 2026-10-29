import XCTest

@MainActor
final class PhotoWorkflowUITests: XCTestCase {
    private let sampleID = "00000000-0000-0000-0000-000000000001"

    func testPendingPhotoCancelReturnsToListWithoutDeletingPhoto() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-pendingPhotosSample", "-recognition"]
        app.launch()
        let row = app.buttons["pendingPhotoOpen-\(sampleID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        XCTAssertTrue(app.buttons["취소"].waitForExistence(timeout: 5))
        app.buttons["취소"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        app.buttons["닫기"].tap()
        XCTAssertTrue(app.buttons["음식 찍기"].waitForExistence(timeout: 5))
    }

    func testPendingPhotoDeletionRequiresConfirmation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-pendingPhotosSample", "-recognition"]
        app.launch()
        let row = app.buttons["pendingPhotoOpen-\(sampleID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        app.buttons["pendingPhotoDelete-\(sampleID)"].tap()
        let dialog = app.alerts["이 사진을 지울까요?"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 3))
        dialog.buttons["취소"].tap()
        XCTAssertTrue(row.exists)
        row.swipeLeft()
        app.buttons["밀어서 사진 지우기"].tap()
        XCTAssertTrue(dialog.waitForExistence(timeout: 3))
        dialog.buttons["사진 지우기"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
    }

    func testPendingPhotoDetailHasVisibleDeleteAction() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-pendingPhotosSample", "-recognition"]
        app.launch()
        let row = app.buttons["pendingPhotoOpen-\(sampleID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        let delete = app.buttons["deletePendingPhoto"]
        for _ in 0..<4 where !delete.isHittable { app.swipeUp() }
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let dialog = app.alerts["이 사진을 지울까요?"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 3))
        dialog.buttons["사진 지우기"].tap()
        XCTAssertTrue(app.navigationBars["확인 안 한 사진"].waitForExistence(timeout: 5))
        XCTAssertFalse(row.exists)
    }

    func testDayClosePhotoSwipeDeletionAndCancelReturnToTimeline() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-dayClosePhotosSample", "-dayCloseStep", "1", "-recognition"]
        app.launch()
        let row = app.buttons["pendingPhotoOpen-\(sampleID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        let delete = app.buttons["pendingPhotoDelete-\(sampleID)"]
        for _ in 0..<4 where !delete.isHittable { app.swipeUp() }
        delete.tap()
        let dialog = app.alerts["이 사진을 지울까요?"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 3))
        dialog.buttons["사진 지우기"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        let failedPhoto = app.buttons["pendingPhotoOpen-00000000-0000-0000-0000-000000000002"]
        for _ in 0..<4 where !failedPhoto.isHittable { app.swipeUp() }
        failedPhoto.tap()
        XCTAssertTrue(app.buttons["취소"].waitForExistence(timeout: 5))
        app.buttons["취소"].tap()
        XCTAssertTrue(failedPhoto.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dayCloseFinish"].isEnabled)
    }

    func testRecognitionPreviewCannotPersistSampleFood() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-recognition"]
        app.launch()
        let notice = app.descendants(matching: .any).matching(identifier: "recognitionPreviewNotice").firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["이대로 저장하기"].isEnabled)
    }

    func testRecognitionCancelReturnsToHome() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-recognition"]
        app.launch()
        let cancel = app.buttons["취소"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 8))
        cancel.tap()
        XCTAssertTrue(app.buttons["음식 찍기"].waitForExistence(timeout: 5), "취소 후 실제 홈 화면으로 돌아와야 한다")
        XCTAssertFalse(app.navigationBars["음식 확인"].exists)
    }
}
