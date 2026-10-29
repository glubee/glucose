import XCTest
@testable import glucose

@MainActor
final class BackupSettingsTests: XCTestCase {
    func testRetryUpdatesStatusAndKeepsQueuedDataOnFailure() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!, progress = DayCloseStore(defaults: defaults)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let photos = PendingPhotoStore(directory: directory, isAuthenticated: { false }, onActivity: { _ in })
        let service = BackupProgressDouble()
        let sync = DataSyncCoordinator(progress: progress, photos: photos, progressService: service,
            photoService: BackupPhotoDouble(), currentAccount: { UUID(uuidString: "00000000-0000-0000-0000-000000000001") }, isEnabled: { true })
        let model = BackupSettingsModel(coordinator: sync, progress: progress, photos: photos, canSync: { true })
        progress.markClosed(ReportDay.today())
        await model.retry()
        XCTAssertEqual(sync.status, .failed)
        XCTAssertTrue(model.hasPending)
        service.fail = false
        await model.retry()
        XCTAssertEqual(sync.status, .saved)
        XCTAssertFalse(model.hasPending)
    }
    func testImportRequiresAnAccountAndReportsSuccessOnlyAfterClaim() {
        var claimed = false, allowed = false
        let model = BackupSettingsModel(canSync: { allowed }, hasLegacy: { !claimed }, importAction: { claimed = true; return true })
        model.importLegacy(); XCTAssertFalse(claimed)
        allowed = true
        model.importLegacy(); XCTAssertTrue(claimed)
        XCTAssertNotNil(model.importMessage)
    }
}
@MainActor
private final class BackupProgressDouble: ProgressSyncServing {
    var fail = true
    func sync(_ request: ProgressSyncRequest) async throws -> ProgressSyncResponse {
        if fail { throw APIError.invalidResponse }
        var state = DayCloseState()
        for op in request.operations { op.apply(to: &state) }
        return ProgressSyncResponse(revision: 1, state: RemoteProgressState(state), acknowledgedOperations: request.operations.map(\.id))
    }
}
@MainActor
private struct BackupPhotoDouble: PhotoSyncServing {
    func pendingPage(cursor: String?) async throws -> PhotoSyncPage { PhotoSyncPage(items: [], nextCursor: nil) }
    func metadata(_ id: UUID) async throws -> SyncedPhoto { throw APIError.invalidResponse }
    func updateMetadata(_ id: UUID, value: PhotoMetadataUpdate) async throws {}
    func dismiss(_ id: UUID) async throws {}
}
