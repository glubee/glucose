import XCTest
@testable import glucose

@MainActor
final class HomeTimelineTests: XCTestCase {
    private let day = ReportDay.date(fromAPIString: "2026-10-29")!

    func testFallbackDotsMatchRawTimelineIncludingInsulinAndExcludeCleanupDuplicates() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let photoID = id(50)
        let pending = [
            PendingPhoto(id: id(10), capturedAt: day.addingTimeInterval(14400), context: .snack),
            PendingPhoto(id: id(11), capturedAt: day.addingTimeInterval(3600), context: .meal, photoId: photoID),
            PendingPhoto(id: id(12), capturedAt: day.addingTimeInterval(10800), context: .meal, isConfirmed: true)
        ]
        try JSONEncoder().encode(pending).write(to: directory.appendingPathComponent("index.json"))
        let photos = PendingPhotoStore(directory: directory, isAuthenticated: { false }, onActivity: { _ in })
        let first = RecordItem.intake(IntakeRecord(id: id(1), occurredAt: day.addingTimeInterval(3600),
                                                  context: .meal, items: [], photoId: photoID))
        let second = food(2, at: 7200)
        let insulin = RecordItem.insulin(InsulinRecord(id: id(3), occurredAt: day.addingTimeInterval(10800), units: 2, kind: "입력"))
        let repo = TimelineRepositoryDouble(intakes: ["start": .init(items: [second, first], nextCursor: nil)],
                                            insulins: ["start": .init(items: [insulin], nextCursor: nil)])
        let model = HomeViewModel(now: day, photos: photos, repository: repo)
        await model.timeline.load(day: day)
        XCTAssertEqual(model.todayRecordCount, 4)
        XCTAssertEqual(model.todayDots.map(\.position), [1.0/24, 2.0/24, 3.0/24, 4.0/24])
        XCTAssertEqual(model.todayDots.map(\.isInsulin), [false, false, true, false])
    }

    // Dropping equal-time items or treating a food page as an analysis episode must fail.
    func testMergedPagesKeepEqualTimesAndRemoveOnlyDuplicateIdentities() async {
        let a = food(1, at: 3600), b = food(2, at: 3600)
        let insulin = RecordItem.insulin(InsulinRecord(id: id(1), occurredAt: day.addingTimeInterval(3600), units: 2, kind: "입력값"))
        let repo = TimelineRepositoryDouble(intakes: ["start": .init(items: [a, a, b], nextCursor: nil)],
                                            insulins: ["start": .init(items: [insulin], nextCursor: nil)])
        let model = RecordsViewModel(repository: repo)
        await model.load()
        XCTAssertEqual(model.items.count, 3)
        XCTAssertEqual(Set(model.items), Set([a, b, insulin]))
    }

    func testFoodFilterReadsPastResponseOnlyPageAndNeverCallsInsulinAPI() async {
        let treatment = food(1, at: 7200, context: .hypoTreatment), meal = food(2, at: 3600)
        let repo = TimelineRepositoryDouble(intakes: [
            "start": .init(items: [treatment], nextCursor: "older"),
            "older": .init(items: [meal], nextCursor: nil)
        ])
        let model = RecordsViewModel(repository: repo)
        await model.load(filter: .food)
        XCTAssertEqual(model.items, [meal])
        XCTAssertEqual(repo.intakeCursors, [nil, "older"])
        XCTAssertTrue(repo.insulinCursors.isEmpty)
    }

    func testResponseFilterUsesUserClassificationAndRefreshRetainsFilter() async {
        let meal = food(1, at: 7000), alcohol = food(2, at: 6000, context: .alcohol)
        let hypo = food(3, at: 5000, context: .hypoTreatment)
        let repo = TimelineRepositoryDouble(intakes: ["start": .init(items: [meal, alcohol, hypo], nextCursor: nil)])
        let model = RecordsViewModel(repository: repo)
        await model.load(filter: .response)
        await model.refresh()
        XCTAssertEqual(model.items, [alcohol, hypo])
        XCTAssertTrue(repo.insulinCursors.isEmpty)
    }

    func testRepeatedCursorStopsWithVisibleErrorInsteadOfRepeatingRows() async {
        let item = food(1, at: 3600)
        let repo = TimelineRepositoryDouble(intakes: [
            "start": .init(items: [item], nextCursor: "loop"),
            "loop": .init(items: [item], nextCursor: "loop")
        ])
        let model = RecordsViewModel(repository: repo)
        await model.load()
        XCTAssertEqual(model.items, [item])
        guard case .error = model.state else { return XCTFail("잘못된 cursor를 오류로 표시해야 함") }
        XCTAssertLessThanOrEqual(repo.intakeCursors.count, 2)
    }

    func testTodayIncludesMidnightExcludesNextDayAndDeduplicatesPendingPhoto() async {
        let photoID = id(50)
        let saved = RecordItem.intake(IntakeRecord(id: id(1), occurredAt: day, context: .meal, items: [], photoId: photoID))
        let late = food(2, at: 86399), next = food(3, at: 86400), yesterday = food(4, at: -1)
        let repo = TimelineRepositoryDouble(intakes: ["start": .init(items: [next, late, saved, yesterday], nextCursor: nil)])
        let model = TodayTimelineViewModel(repository: repo)
        await model.load(day: day)
        let pending = PendingPhoto(id: id(5), capturedAt: day.addingTimeInterval(7200), context: .snack)
        let duplicate = PendingPhoto(id: id(6), capturedAt: day, context: .meal, photoId: photoID)
        let confirmed = PendingPhoto(id: id(7), capturedAt: day, context: .meal, isConfirmed: true)
        let old = PendingPhoto(id: id(8), capturedAt: day.addingTimeInterval(-1), context: .meal)
        let rows = model.entries(photos: [pending, duplicate, confirmed, old])
        XCTAssertEqual(rows.map(\.occurredAt), [day, day.addingTimeInterval(7200), day.addingTimeInterval(86399)])
        XCTAssertEqual(rows.count, 3)
    }

    func testTodayFetchesAdditionalPagesAndKeepsPendingWhenNetworkFails() async {
        let todayItems = (0..<23).map { food($0 + 1, at: Double(80000 - $0 * 100)) }
        let repo = TimelineRepositoryDouble(intakes: [
            "start": .init(items: Array(todayItems.prefix(20)), nextCursor: "older"),
            "older": .init(items: Array(todayItems.suffix(3)) + [food(90, at: -1)], nextCursor: nil)
        ])
        let model = TodayTimelineViewModel(repository: repo)
        await model.load(day: day)
        XCTAssertEqual(model.entries(photos: []).count, 23)
        repo.fails = true
        await model.load(day: day)
        let photo = PendingPhoto(id: id(99), capturedAt: day, context: .meal)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.entries(photos: [photo]).contains { $0.id == "pending-\(photo.id)" })
    }

    func testFilterChangeRejectsOldResponse() async {
        let repository = FilterRaceRepository()
        let model = RecordsViewModel(repository: repository)
        let first = Task { await model.load() }
        while repository.continuation == nil { await Task.yield() }
        await model.load(filter: .insulin)
        repository.continuation?.resume(returning: .init(items: [food(1, at: 3600)], nextCursor: nil))
        await first.value
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertEqual(model.state, .loaded)
    }

    private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "30000000-0000-0000-0000-%012d", n))! }
    private func food(_ n: Int, at seconds: Double, context: IntakeContext = .meal) -> RecordItem {
        .intake(IntakeRecord(id: id(n), occurredAt: day.addingTimeInterval(seconds), context: context,
                             items: [FoodItem(id: id(n + 1000), name: "합성 음식", count: 1, unit: "개")]))
    }
}

@MainActor
final class TimelineRepositoryDouble: RecordRepository {
    let intakes: [String: RecordPage]
    let insulins: [String: RecordPage]
    var intakeCursors: [String?] = []
    var insulinCursors: [String?] = []
    var fails = false
    init(intakes: [String: RecordPage] = [:], insulins: [String: RecordPage] = [:]) {
        self.intakes = intakes; self.insulins = insulins
    }
    func fetchIntakePage(cursor: String?, limit: Int) async throws -> RecordPage {
        intakeCursors.append(cursor)
        if fails { throw URLError(.notConnectedToInternet) }
        return intakes[cursor ?? "start"] ?? .init(items: [], nextCursor: nil)
    }
    func fetchInsulinPage(cursor: String?, limit: Int) async throws -> RecordPage {
        insulinCursors.append(cursor)
        if fails { throw URLError(.notConnectedToInternet) }
        return insulins[cursor ?? "start"] ?? .init(items: [], nextCursor: nil)
    }
}

@MainActor
private final class FilterRaceRepository: RecordRepository {
    var continuation: CheckedContinuation<RecordPage, Error>?
    private var calls = 0
    func fetchIntakePage(cursor: String?, limit: Int) async throws -> RecordPage {
        calls += 1
        if calls == 1 { return try await withCheckedThrowingContinuation { continuation = $0 } }
        return .init(items: [], nextCursor: nil)
    }
    func fetchInsulinPage(cursor: String?, limit: Int) async throws -> RecordPage { .init(items: [], nextCursor: nil) }
}
