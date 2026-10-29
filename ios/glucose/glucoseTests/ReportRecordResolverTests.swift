import XCTest
@testable import glucose

@MainActor
final class ReportRecordResolverTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_790_000_000)
    private let photoID = UUID()
    private var mark: DailyReport.Episode.IntakeMark {
        .init(occurredAt: time, context: .meal, photoId: photoID, foods: ["밥 1공기"])
    }

    func testLookupFindsExactPhotoTimeAndContextOnLaterPage() async throws {
        let matching = record()
        let reader = ReportReaderDouble(pages: [
            .init(items: [record(time: time.addingTimeInterval(3600))], nextCursor: "page-2"),
            .init(items: [matching], nextCursor: nil)
        ])
        let result = try await ReportRecordResolver(reader: reader).resolve(mark: mark)
        XCTAssertEqual(result, .found(matching.toRecord()))
        XCTAssertEqual(reader.cursors, [nil, "page-2"])
    }

    func testDuplicateMatchesAcrossPagesAreAmbiguous() async throws {
        let reader = ReportReaderDouble(pages: [
            .init(items: [record()], nextCursor: "page-2"),
            .init(items: [record()], nextCursor: nil)
        ])
        let result = try await ReportRecordResolver(reader: reader).resolve(mark: mark)
        XCTAssertEqual(result, .ambiguous)
    }

    func testPhotoAndContextMustBothMatch() async throws {
        let reader = ReportReaderDouble(pages: [.init(items: [record(photo: UUID()), record(context: "SNACK")], nextCursor: nil)])
        let result = try await ReportRecordResolver(reader: reader).resolve(mark: mark)
        XCTAssertEqual(result, .missing)
    }

    func testLookupStopsOnceRecordsAreOlderThanTheTarget() async throws {
        let reader = ReportReaderDouble(pages: [.init(items: [record(time: time.addingTimeInterval(-1))], nextCursor: "older")])
        let result = try await ReportRecordResolver(reader: reader).resolve(mark: mark)
        XCTAssertEqual(result, .missing)
        XCTAssertEqual(reader.cursors.count, 1)
    }

    func testRepeatedCursorDoesNotLoopOrPickAnUnverifiedRecord() async throws {
        let newer = record(time: time.addingTimeInterval(3600))
        let reader = ReportReaderDouble(pages: [.init(items: [newer], nextCursor: "same"),
                                               .init(items: [newer], nextCursor: "same")])
        let result = try await ReportRecordResolver(reader: reader).resolve(mark: mark)
        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(reader.cursors.count, 2)
    }

    func testPageLimitDoesNotClaimAUniqueMatchBeforeSearchCompletes() async throws {
        let reader = ReportReaderDouble(pages: [.init(items: [record()], nextCursor: "more")])
        let result = try await ReportRecordResolver(reader: reader, maxPages: 1).resolve(mark: mark)
        XCTAssertEqual(result, .unavailable)
    }

    func testNetworkFailureRemainsAnErrorInsteadOfMissingRecord() async {
        let reader = ReportReaderDouble(pages: [])
        reader.shouldFail = true
        do {
            _ = try await ReportRecordResolver(reader: reader).resolve(mark: mark)
            XCTFail("네트워크 실패를 찾을 수 없음으로 처리하면 안 된다")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
    }

    func testCancelledLookupDoesNotReturnARecord() async {
        let reader = ReportReaderDouble(pages: [.init(items: [record()], nextCursor: nil)])
        let resolver = ReportRecordResolver(reader: reader)
        let selected = mark
        let task = Task { try await resolver.resolve(mark: selected) }
        task.cancel()
        do { _ = try await task.value; XCTFail("취소한 조회는 완료하면 안 된다") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    private func record(time: Date? = nil, photo: UUID? = nil, context: String = "MEAL") -> IntakeResponse {
        IntakeResponse(id: UUID(), context: context, occurredAt: time ?? self.time, photoId: photo ?? photoID,
                       items: [.init(id: UUID(), name: "밥", count: 1, unit: "공기", categoryHint: nil, tags: [], sugarGrams: nil)],
                       createdAt: self.time, updatedAt: self.time)
    }
}

@MainActor
private final class ReportReaderDouble: ReportRecordReading {
    let pages: [PageResponse<IntakeResponse>]
    var cursors: [String?] = []
    var shouldFail = false
    init(pages: [PageResponse<IntakeResponse>]) { self.pages = pages }
    func page(cursor: String?) async throws -> PageResponse<IntakeResponse> {
        if shouldFail { throw URLError(.notConnectedToInternet) }
        let index = cursors.count
        cursors.append(cursor)
        guard index < pages.count else { throw APIError.invalidResponse }
        return pages[index]
    }
}
