import XCTest
@testable import glucose

@MainActor
final class ReportChartTests: XCTestCase {
    private var day: Date { ReportDay.calendar.date(from: DateComponents(year: 2026, month: 10, day: 29))! }

    func testMissingFlagBreaksLineEvenWhenAValueIsPresent() {
        let points = GlucosePoint.points(from: [
            .init(time: "08:00", value: 100, flag: "NORMAL"),
            .init(time: "08:15", value: 999, flag: "MISSING"),
            .init(time: "08:30", value: 120, flag: "NORMAL")
        ], on: day, calendar: ReportDay.calendar)
        XCTAssertEqual(points.map(\.value), [100, 120])
        XCTAssertNotEqual(points.first?.segment, points.last?.segment)
    }

    func testMalformedClockTimesDoNotBecomeValidReadings() {
        let points = GlucosePoint.points(from: [
            .init(time: "08:x:00", value: 100, flag: "NORMAL"),
            .init(time: "24:00", value: 110, flag: "NORMAL"),
            .init(time: "08:60", value: 120, flag: "NORMAL"),
            .init(time: "09:00", value: 130, flag: "NORMAL")
        ], on: day, calendar: ReportDay.calendar)
        XCTAssertEqual(points.map(\.value), [130])
    }
    func testPhotoAnchorIsLinearOnlyInsideOneObservedSegment() {
        let points = [GlucosePoint(time: at(8), value: 100, segment: 0),
                      GlucosePoint(time: at(8, 15), value: 160, segment: 0)]
        let curve = GlucoseCurve(points: points)
        XCTAssertEqual(curve.anchorValue(at: at(8, 5)), 120)
        XCTAssertEqual(curve.nearestObservedPoint(to: at(8, 5))?.value, 100)
        XCTAssertEqual(curve.anchorValue(at: at(8, 15)), 160)
    }

    func testMissingSegmentNeverUsesNearestReadingAsSelectedValue() {
        let curve = GlucoseCurve(points: [
            GlucosePoint(time: at(8), value: 100, segment: 0),
            GlucosePoint(time: at(8, 30), value: 160, segment: 1)
        ])
        XCTAssertNil(curve.anchorValue(at: at(8, 15)))
        XCTAssertNil(curve.nearestObservedPoint(to: at(8, 5)))
        XCTAssertNil(curve.anchorValue(at: at(7, 59)))
        XCTAssertEqual(curve.nearestObservedPoint(to: at(8))?.value, 100)
    }

    func testLongGapsRemainMissingEvenIfSegmentIDIsIncorrect() {
        let curve = GlucoseCurve(points: [
            GlucosePoint(time: at(8), value: 100, segment: 0),
            GlucosePoint(time: at(9), value: 160, segment: 0)
        ])
        XCTAssertNil(curve.anchorValue(at: at(8, 30)))
    }

    func testThirtyMinuteGroupsDoNotChainAcrossLongerIntervals() {
        let groups = ChartPhotoGroup.make(marks: [photo(at(8)), photo(at(8, 25)), photo(at(8, 50))],
                                           day: day, points: [])
        XCTAssertEqual(groups.map { $0.members.count }, [2, 1])
        XCTAssertEqual(groups.map(\.time), [at(8), at(8, 50)])
    }

    func testThirtyMinuteBoundaryIsInclusive() {
        let groups = ChartPhotoGroup.make(marks: [photo(at(8)), photo(at(8, 30)), photo(at(8, 31))],
                                           day: day, points: [])
        XCTAssertEqual(groups.map { $0.members.count }, [2, 1])
    }

    func testDuplicateTimestampsAndPhotoIDsDoNotLoseRecords() {
        let mark = photo(at(8))
        let groups = ChartPhotoGroup.make(marks: [mark, mark, photo(at(8))], day: day, points: [])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].members.count, 3)
        XCTAssertEqual(Set(groups[0].members.map(\.id)).count, 3)
    }

    func testOnlyPhotosFromTheReportDayAreGrouped() {
        let noPhoto = DailyReport.Episode.IntakeMark(occurredAt: at(9), context: .meal, photoId: nil)
        let groups = ChartPhotoGroup.make(marks: [photo(day.addingTimeInterval(-1)), photo(at(8)), noPhoto,
                                                  photo(day.addingTimeInterval(86_400))], day: day, points: [])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].time, at(8))
    }

    func testPhotoInGapHasNoCurveAnchor() {
        let groups = ChartPhotoGroup.make(marks: [photo(at(8, 15))], day: day, points: [
            .init(time: at(8), value: 100, segment: 0), .init(time: at(8, 30), value: 160, segment: 1)
        ])
        XCTAssertNil(groups[0].anchorValue)
    }

    func testPhotoPlacementsStayInsidePlotAndDoNotOverlap() {
        let bounds = CGSize(width: 200, height: 150)
        let placements = PhotoMarkerLayout.place(anchors: [
            .init(id: "left", point: CGPoint(x: 0, y: 10)),
            .init(id: "nearby", point: CGPoint(x: 2, y: 12)),
            .init(id: "right", point: CGPoint(x: 199, y: 140))
        ], bounds: bounds)
        XCTAssertTrue(placements.contains { $0.id == "left" })
        XCTAssertTrue(placements.contains { $0.id == "right" })
        for placement in placements { XCTAssertTrue(CGRect(origin: .zero, size: bounds).contains(placement.frame)) }
        for first in placements.indices {
            for second in placements.indices where second > first {
                XCTAssertFalse(placements[first].frame.intersects(placements[second].frame))
            }
        }
    }

    func testTooSmallPlotAndInvalidAnchorsAreSafelyOmitted() {
        XCTAssertTrue(PhotoMarkerLayout.place(anchors: [.init(id: "a", point: .zero)],
                                              bounds: CGSize(width: 20, height: 20)).isEmpty)
        XCTAssertTrue(PhotoMarkerLayout.place(anchors: [.init(id: "a", point: CGPoint(x: Double.nan, y: 5))],
                                              bounds: CGSize(width: 200, height: 150)).isEmpty)
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        ReportDay.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func photo(_ time: Date) -> DailyReport.Episode.IntakeMark {
        .init(occurredAt: time, context: .meal, photoId: UUID(), foods: ["밥 1공기"])
    }

}
