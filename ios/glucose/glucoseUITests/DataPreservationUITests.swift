import XCTest

@MainActor
final class DataPreservationUITests: XCTestCase {
    func testBackupRetryShowsAnExplicitLocalVerificationResult() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-backupSamples"]; app.launch()
        XCTAssertTrue(app.staticTexts["로컬 검증 예시 · 서버에 연결하지 않아요"].waitForExistence(timeout: 6))
        let retry = app.buttons["backupRetry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["백업 연결을 확인하지 못했어요"].waitForExistence(timeout: 6))
        retry.tap()
        XCTAssertTrue(app.staticTexts["로컬 검증을 마쳤어요"].waitForExistence(timeout: 6))
    }

    func testLegacyImportRequiresConfirmationThenRemovesTheImportAction() {
        let app = launchSample()
        let importButton = app.buttons["backupImportLegacy"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 6))
        importButton.tap()
        XCTAssertTrue(app.buttons["이 계정으로 가져오기"].waitForExistence(timeout: 3))
        app.buttons["취소"].tap()
        XCTAssertTrue(importButton.exists)
        importButton.tap()
        app.buttons["이 계정으로 가져오기"].tap()
        XCTAssertTrue(app.staticTexts["이전 기기 기록을 가져왔어요. 백업 상태를 확인해 주세요."].waitForExistence(timeout: 6))
        XCTAssertTrue(importButton.waitForNonExistence(timeout: 6))
    }

    func testRestoredRemotePhotoCancelKeepsThePhoto() {
        let app = launchSample()
        app.buttons["복원한 사진 보기"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "pendingPhotoOpen-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 6))
        row.tap()
        XCTAssertTrue(app.navigationBars["음식 확인"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.images["확인 대기 사진"].waitForExistence(timeout: 6))
        app.buttons["취소"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 6))
    }

    func testConfirmingRestoredPhotoReturnsToAnEmptyPendingList() {
        let app = launchSample()
        app.buttons["복원한 사진 보기"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "pendingPhotoOpen-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 6))
        row.tap()
        let save = app.buttons["이대로 저장하기"]
        XCTAssertTrue(save.waitForExistence(timeout: 6))
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["확인할 사진이 없어요"].waitForExistence(timeout: 6))
        XCTAssertTrue(row.waitForNonExistence(timeout: 6))
    }

    private func launchSample() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-backupSamples"]; app.launch()
        XCTAssertTrue(app.staticTexts["백업 연결을 확인하지 못했어요"].waitForExistence(timeout: 6))
        return app
    }

}
