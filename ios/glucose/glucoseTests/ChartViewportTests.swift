import XCTest
@testable import glucose

@MainActor
final class ChartViewportTests: XCTestCase {
    private var day: Date { ReportDay.today() }
    func testPresetCentersOnChosenTimeAndClampsToDay() {
        var view = ChartViewport(day: day)
        view.setHours(3, around: day.addingTimeInterval(8 * 3600))
        XCTAssertEqual(view.start.timeIntervalSince(day), 6.5 * 3600, accuracy: 0.01)
        view.move(by: -86_400)
        XCTAssertEqual(view.start, day)
        view.move(by: 86_400)
        XCTAssertEqual(view.start.timeIntervalSince(day), 21 * 3600, accuracy: 0.01)
    }
    func testReturningToDayResetsStart() {
        var view = ChartViewport(day: day)
        view.setHours(3, around: day.addingTimeInterval(8 * 3600))
        view.setHours(24)
        XCTAssertEqual(view.start, day)
        XCTAssertEqual(view.duration, 86_400)
    }
    func testPinchKeepsAnchorTimeAndClampsZoom() {
        var view = ChartViewport(day: day)
        view.zoom(by: 2, anchor: 0.25)
        XCTAssertEqual(view.duration, 12 * 3600)
        XCTAssertEqual(view.start.timeIntervalSince(day) + view.duration * 0.25, 6 * 3600, accuracy: 0.01)
        view.zoom(by: 100, anchor: 0.5)
        XCTAssertEqual(view.duration, 3 * 3600)
        view.zoom(by: 0.001, anchor: 0.5)
        XCTAssertEqual(view.duration, 24 * 3600)
        XCTAssertEqual(view.start, day)
    }
    func testInvalidGestureDoesNotCorruptViewport() {
        var view = ChartViewport(day: day)
        view.zoom(by: .nan, anchor: 0.5)
        view.zoom(by: 0, anchor: .infinity)
        XCTAssertEqual(view.start, day)
        XCTAssertEqual(view.duration, 86_400)
    }
    func testScrollPositionClampsAtBothBoundaries() {
        var view = ChartViewport(day: day)
        view.setHours(6)
        view.scroll(to: day.addingTimeInterval(-1000))
        XCTAssertEqual(view.start, day)
        view.scroll(to: day.addingTimeInterval(86_400))
        XCTAssertEqual(view.start.timeIntervalSince(day), 18 * 3600)
    }
}
