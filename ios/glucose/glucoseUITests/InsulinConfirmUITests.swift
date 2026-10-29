import XCTest

/// 인슐린 투여 확인: 실제 투여 시각 바꾸기, 평소 값 고치기, 다른 인슐린 넣기
@MainActor
final class InsulinConfirmUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-insulinConfirm"]
        app.launch()
        return app
    }

    func testCompactCardCanChangeActualTime() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["지금 맞을 인슐린"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["insulinTimePicker"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["실제 투여 시각"].exists)
    }

    func testChangingUnitsOffersToUpdateUsualValue() {
        let app = launch()
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "초속효성 인슐린 4단위")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        card.tap()
        let units = app.textFields["단위"]
        XCTAssertTrue(units.waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["insulinUpdateUsual"].exists)
        units.tap()
        units.typeText(XCUIKeyboardKey.delete.rawValue + "5")
        XCTAssertTrue(app.switches["insulinUpdateUsual"].waitForExistence(timeout: 5))
    }

    func testOtherInsulinStartsBlankAndOffersToRemember() {
        let app = launch()
        let other = app.buttons["+ 다른 인슐린"]
        XCTAssertTrue(other.waitForExistence(timeout: 8))
        other.tap()
        let kind = app.textFields["insulinKindField"]
        XCTAssertTrue(kind.waitForExistence(timeout: 5))
        XCTAssertEqual((kind.value as? String) ?? "", "예: 초속효성 인슐린")
        XCTAssertTrue(app.switches["평소 인슐린에 추가하기"].exists)
    }
}
