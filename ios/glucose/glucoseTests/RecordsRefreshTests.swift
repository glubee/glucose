import XCTest
@testable import glucose

@MainActor
final class RecordsRefreshTests: XCTestCase {
    func testOldPageCannotReappearAfterRefresh() async {
        let old = record(name: "이전 기록")
        let current = record(name: "새 기록")
        let repository = DelayedRecordRepository(current: current)
        let model = RecordsViewModel(repository: repository)
        let first = Task { await model.load() }
        while repository.continuation == nil { await Task.yield() }
        await model.refresh()
        repository.continuation?.resume(returning: RecordPage(items: [old], nextCursor: nil))
        await first.value
        XCTAssertEqual(model.items.map(\.id), [current.id])
        XCTAssertEqual(model.state, .loaded)
    }

    func testOldPageFailureDoesNotReplaceRefreshedState() async {
        let current = record(name: "새 기록")
        let repository = DelayedRecordRepository(current: current)
        let model = RecordsViewModel(repository: repository)
        let first = Task { await model.load() }
        while repository.continuation == nil { await Task.yield() }
        await model.refresh()
        repository.continuation?.resume(throwing: URLError(.notConnectedToInternet))
        await first.value
        XCTAssertEqual(model.items.map(\.id), [current.id])
        XCTAssertEqual(model.state, .loaded)
    }

    private func record(name: String) -> RecordItem {
        .intake(IntakeRecord(id: UUID(), occurredAt: .now, context: .meal,
                             items: [FoodItem(id: UUID(), name: name, count: 1, unit: "개")]))
    }
}

@MainActor
private final class DelayedRecordRepository: RecordRepository {
    let current: RecordItem
    var calls = 0
    var continuation: CheckedContinuation<RecordPage, Error>?
    init(current: RecordItem) { self.current = current }

    func fetchIntakePage(cursor: String?, limit: Int) async throws -> RecordPage {
        calls += 1
        if calls == 1 {
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        return RecordPage(items: [current], nextCursor: nil)
    }

    func fetchInsulinPage(cursor: String?, limit: Int) async throws -> RecordPage {
        RecordPage(items: [], nextCursor: nil)
    }
}
