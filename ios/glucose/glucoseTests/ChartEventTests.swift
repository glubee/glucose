import XCTest
@testable import glucose

@MainActor
final class ChartEventTests: XCTestCase {
    private var day: Date { ReportDay.today() }

    func testEventsPreserveSameTimeAndSamePhotoRecords() {
        let mark = DailyReport.Episode.IntakeMark(occurredAt: day.addingTimeInterval(8 * 3600), context: .meal, photoId: UUID())
        let events = ChartEvent.make(day: day, episodes: [episode([mark, mark])],
                                     insulinEvents: [.init(occurredAt: mark.occurredAt, units: 4, kind: "식사")])
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(Set(events.map(\.id)).count, 3)
        XCTAssertEqual(events.filter { $0.symbolName == "syringe" }.count, 1)
    }

    func testEventsOutsideReportDayAreExcluded() {
        let marks = [-1.0, 0, 86_400].map { DailyReport.Episode.IntakeMark(occurredAt: day.addingTimeInterval($0), context: .meal, photoId: nil) }
        let events = ChartEvent.make(day: day, episodes: [episode(marks)], insulinEvents: [])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.time, day)
    }

    func testScreenSpaceClustersSplitWhenZoomed() {
        let sample = ReportSamples.daily(day).0
        let events = ChartEvent.make(day: day, episodes: sample.episodes, insulinEvents: sample.insulinEvents ?? [])
        let full = ChartEventCluster.make(events: events, range: day...day.addingTimeInterval(86_400), width: 320)
        let zoomed = ChartEventCluster.make(events: events,
            range: day.addingTimeInterval(7 * 3600)...day.addingTimeInterval(10 * 3600), width: 320)
        XCTAssertLessThan(full.count, events.count)
        XCTAssertTrue(full.contains { $0.events.count > 1 })
        XCTAssertGreaterThan(zoomed.count, 1)
        XCTAssertEqual(zoomed.flatMap(\.events).count, 4)
    }

    func testClustersDoNotDropRecordsAndStayApartAtEdges() {
        let sample = ReportSamples.daily(day).0
        let events = ChartEvent.make(day: day, episodes: sample.episodes, insulinEvents: sample.insulinEvents ?? [])
        let groups = ChartEventCluster.make(events: events, range: day...day.addingTimeInterval(86_400), width: 200)
        XCTAssertEqual(groups.flatMap(\.events).map(\.id).sorted(), events.map(\.id).sorted())
        for pair in zip(groups, groups.dropFirst()) { XCTAssertGreaterThanOrEqual(pair.1.x - pair.0.x, 60) }
        XCTAssertTrue(groups.allSatisfy { $0.x >= 30 && $0.x <= 170 })
    }

    func testTinyPlotKeepsOneAccessibleClusterAndInvalidWidthDoesNotCrash() {
        let sample = ReportSamples.daily(day).0
        let events = ChartEvent.make(day: day, episodes: sample.episodes, insulinEvents: sample.insulinEvents ?? [])
        let range = day...day.addingTimeInterval(86_400)
        XCTAssertEqual(ChartEventCluster.make(events: events, range: range, width: 40).first?.events.count, events.count)
        XCTAssertTrue(ChartEventCluster.make(events: events, range: range, width: .nan).isEmpty)
    }

    func testContentChangeInvalidatesPresentationIdentity() {
        let first = DailyReport.Episode.IntakeMark(occurredAt: day, context: .meal, photoId: nil, foods: ["밥"])
        let second = DailyReport.Episode.IntakeMark(occurredAt: day, context: .snack, photoId: nil, foods: ["우유"])
        let a = ChartEvent.make(day: day, episodes: [episode([first])], insulinEvents: [])
        let b = ChartEvent.make(day: day, episodes: [episode([second])], insulinEvents: [])
        XCTAssertNotEqual(a.map(\.fingerprint), b.map(\.fingerprint))
    }

    func testSampleSummaryMatchesPlottedObservations() {
        let (report, points) = ReportSamples.daily(day)
        XCTAssertEqual(report.glucose?.readingsCount, points.count)
        XCTAssertEqual(report.glucose?.min, points.map(\.value).min())
        XCTAssertEqual(report.glucose?.max, points.map(\.value).max())
        XCTAssertEqual(report.glucose?.average ?? 0, Double(points.map(\.value).reduce(0, +)) / Double(points.count), accuracy: 0.01)
        XCTAssertEqual(report.glucose?.coverageRatio ?? 0, Double(points.count) / 96, accuracy: 0.001)
    }

    func testDailySampleFoodEvidenceMatchesPlottedObservations() {
        let (_, points) = ReportSamples.daily(day)
        let observation = ReportSamples.food(day, weekly: false).observations[0]
        for reading in [observation.baseline, observation.peak, observation.endReading].compactMap({ $0 }) {
            XCTAssertEqual(points.first(where: { $0.time == reading.time })?.value, reading.value)
        }
    }

    func testSampleObservationCountsOnlyPostIntakeReadingsAndIsLimited() {
        let observation = ReportSamples.food(day, weekly: false).observations[0]
        let points = ReportSamples.daily(day).1.filter {
            $0.time > observation.occurredAt && $0.time <= observation.windowEndAt
        }
        XCTAssertEqual(observation.readingsCount, points.count)
        XCTAssertEqual(observation.expectedReadingsCount, 16)
        XCTAssertEqual(observation.coverageRatio, Double(points.count) / 16, accuracy: 0.001)
        XCTAssertEqual(observation.status, "LIMITED")
    }

    private func episode(_ marks: [DailyReport.Episode.IntakeMark]) -> DailyReport.Episode {
        .init(startAt: day, originalContext: .meal, effectiveContext: .meal, autoReclassified: false,
              windowEndAt: day.addingTimeInterval(86_400), reboundDetected: nil, intakeCount: marks.count, intakes: marks)
    }
}
