import XCTest
@testable import glucose

@MainActor
final class ReportInsulinResolverTests: XCTestCase {
    private var marker: DailyReport.InsulinMarker { .init(occurredAt: ReportDay.today(), units: 4, kind: "식사") }
    private func record(_ offset: TimeInterval = 0, units: Double = 4) -> RecordItem {
        .insulin(.init(id: UUID(), occurredAt: marker.occurredAt.addingTimeInterval(offset), units: units, kind: "식사"))
    }
    func testFindsExactInsulinOnLaterPage() async throws {
        let item = record()
        let reader = InsulinReader(pages: [.init(items: [record(100)], nextCursor: "more"), .init(items: [item], nextCursor: nil)])
        let result = try await ReportInsulinRecordResolver(reader: reader).resolve(marker)
        XCTAssertEqual(result, .found(item))
    }
    func testSameTimeDuplicatesAreAmbiguous() async throws {
        let reader = InsulinReader(pages: [.init(items: [record(), record()], nextCursor: nil)])
        let result = try await ReportInsulinRecordResolver(reader: reader).resolve(marker)
        XCTAssertEqual(result, .ambiguous)
    }
    func testUnitsMustMatchAndRepeatedCursorCannotPickUnverifiedRecord() async throws {
        let reader = InsulinReader(pages: [.init(items: [record(units: 5)], nextCursor: nil)])
        let result = try await ReportInsulinRecordResolver(reader: reader).resolve(marker)
        XCTAssertEqual(result, .missing)
        let looping = InsulinReader(pages: [.init(items: [record()], nextCursor: "same"), .init(items: [record(100)], nextCursor: "same")])
        let unavailable = try await ReportInsulinRecordResolver(reader: looping).resolve(marker)
        XCTAssertEqual(unavailable, .unavailable)
    }
}

private final class InsulinReader: RecordRepository {
    let pages: [RecordPage]
    var count = 0
    init(pages: [RecordPage]) { self.pages = pages }
    func fetchIntakePage(cursor: String?, limit: Int) async throws -> RecordPage { throw APIError.invalidResponse }
    func fetchInsulinPage(cursor: String?, limit: Int) async throws -> RecordPage {
        defer { count += 1 }
        return pages[count]
    }
}
