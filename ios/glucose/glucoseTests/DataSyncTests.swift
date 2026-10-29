import XCTest
@testable import glucose

@MainActor
final class DataSyncTests: XCTestCase {
    private final class Owner { var id = UUID() }
    private struct Environment {
        let progress: DayCloseStore; let photos: PendingPhotoStore
        let service: SyncProgressDouble; let owner: Owner; let coordinator: DataSyncCoordinator
    }
    private func environment() -> Environment {
        let progress = DayCloseStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, accountScoped: true)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let photos = PendingPhotoStore(directory: folder, isAuthenticated: { false }, onActivity: { _ in }, accountScoped: true)
        let owner = Owner(), service = SyncProgressDouble()
        progress.activateAccount(owner.id); photos.activateAccount(owner.id)
        let coordinator = DataSyncCoordinator(progress: progress, photos: photos, progressService: service,
            photoService: EmptyPhotoSync(), currentAccount: { owner.id }, isEnabled: { true })
        return Environment(progress: progress, photos: photos, service: service, owner: owner, coordinator: coordinator)
    }
    private func day(_ offset: Int) -> Date { ReportDay.calendar.date(byAdding: .day, value: -offset, to: ReportDay.today())! }

    func testQueuedProgressRetriesSameIdentityAfterOfflineFailure() async throws {
        let env = environment()
        env.progress.markClosed(day(1))
        let id = try XCTUnwrap(env.progress.makeSyncRequest().operations.first?.id)
        env.service.fail = true
        await env.coordinator.refresh()
        XCTAssertEqual(env.coordinator.status, .failed)
        XCTAssertTrue(env.progress.hasPendingChanges)
        env.service.fail = false
        await env.coordinator.refresh()
        XCTAssertEqual(env.service.requests.map { $0.operations.first?.id }, [id, id])
        XCTAssertFalse(env.progress.hasPendingChanges)
        XCTAssertEqual(env.coordinator.status, .saved)
    }

    func testNewChangeDuringResponseIsRetainedAndSentNext() async throws {
        let env = environment(), entered = expectation(description: "request entered")
        env.progress.markClosed(day(2)); env.service.pauseNext = true
        env.service.onEntered = { entered.fulfill() }
        let work = Task { await env.coordinator.refresh() }
        await fulfillment(of: [entered], timeout: 2)
        env.progress.markClosed(day(1))
        try XCTUnwrap(env.service.continuation).resume()
        await work.value
        XCTAssertEqual(env.service.requests.count, 2)
        XCTAssertEqual(env.progress.closedDays.count, 2)
        XCTAssertFalse(env.progress.hasPendingChanges)
    }

    func testAccountSwitchCannotApplyAnOlderResponse() async throws {
        let env = environment(), entered = expectation(description: "request entered")
        env.progress.markClosed(day(1)); env.service.pauseNext = true
        env.service.onEntered = { entered.fulfill() }
        let work = Task { await env.coordinator.refresh() }
        await fulfillment(of: [entered], timeout: 2)
        env.owner.id = UUID()
        env.coordinator.invalidate()
        env.progress.activateAccount(env.owner.id); env.photos.activateAccount(env.owner.id)
        try XCTUnwrap(env.service.continuation).resume()
        await work.value
        XCTAssertTrue(env.progress.closedDays.isEmpty)
        XCTAssertFalse(env.progress.hasPendingChanges)
        XCTAssertEqual(env.coordinator.status, .idle)
    }

    func testLargeOfflineQueueIsAcknowledgedInBoundedBatches() async {
        let env = environment()
        for offset in 1...205 { env.progress.markClosed(day(offset)) }
        await env.coordinator.refresh()
        XCTAssertEqual(env.service.requests.map { $0.operations.count }, [100,100,5])
        XCTAssertEqual(env.progress.closedDays.count, 205)
        XCTAssertFalse(env.progress.hasPendingChanges)
        XCTAssertEqual(env.coordinator.status, .saved)
    }

    func testMissingAcknowledgementRetainsQueueWithoutRetryLoop() async {
        let env = environment(); env.progress.markClosed(day(1)); env.service.acknowledge = false
        await env.coordinator.refresh()
        XCTAssertEqual(env.service.requests.count, 1)
        XCTAssertTrue(env.progress.hasPendingChanges)
        XCTAssertEqual(env.coordinator.status, .failed)
    }

    func testConcurrentRefreshesShareTheSameRequest() async throws {
        let env = environment(), entered = expectation(description: "request entered")
        env.service.pauseNext = true; env.service.onEntered = { entered.fulfill() }
        let first = Task { await env.coordinator.refresh() }
        await fulfillment(of: [entered], timeout: 2)
        let second = Task { await env.coordinator.refresh() }
        await Task.yield()
        try XCTUnwrap(env.service.continuation).resume()
        await first.value; await second.value
        XCTAssertEqual(env.service.requests.count, 1)
    }
}

@MainActor
private final class SyncProgressDouble: ProgressSyncServing {
    var fail = false, acknowledge = true, pauseNext = false
    var requests: [ProgressSyncRequest] = []
    var continuation: CheckedContinuation<Void, Never>?
    var onEntered: (() -> Void)?
    private var state = DayCloseState()
    private var revision: Int64 = 0
    func sync(_ request: ProgressSyncRequest) async throws -> ProgressSyncResponse {
        requests.append(request)
        if fail { throw APIError.invalidResponse }
        for operation in request.operations { operation.apply(to: &state) }
        revision += 1
        let response = ProgressSyncResponse(revision: revision, state: RemoteProgressState(state),
            acknowledgedOperations: acknowledge ? request.operations.map(\.id) : [])
        if pauseNext {
            pauseNext = false
            await withCheckedContinuation { continuation = $0; onEntered?() }
        }
        return response
    }
}
@MainActor
private struct EmptyPhotoSync: PhotoSyncServing {
    func pendingPage(cursor: String?) async throws -> PhotoSyncPage { PhotoSyncPage(items: [], nextCursor: nil) }
    func metadata(_ id: UUID) async throws -> SyncedPhoto { throw APIError.invalidResponse }
    func updateMetadata(_ id: UUID, value: PhotoMetadataUpdate) async throws {}
    func dismiss(_ id: UUID) async throws {}
}
