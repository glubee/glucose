#if DEBUG
import SwiftUI

/// Development fixtures exercise the real coordinator and file stores without a live account.
@MainActor
@Observable
final class SyncSamples {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-backupSamples") }
    let photos: PendingPhotoStore
    let model: BackupSettingsModel

    init() {
        let progress = DayCloseStore(defaults: UserDefaults(suiteName: "sync-preview-\(UUID())")!)
        progress.markClosed(ReportDay.today())
        photos = PendingPhotoStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("sync-preview-\(UUID())"),
                                   isAuthenticated: { false }, onActivity: { _ in })
        let coordinator = DataSyncCoordinator(progress: progress, photos: photos,
            progressService: SampleProgress(), photoService: SamplePhotos(),
            currentAccount: { UUID(uuidString: "40000000-0000-0000-0000-000000000001") }, isEnabled: { true })
        let legacy = BackupSampleLegacyFlag()
        model = BackupSettingsModel(coordinator: coordinator, progress: progress, photos: photos, isExample: true,
            canSync: { true }, hasLegacy: { legacy.available }, importAction: {
                legacy.available = false
                progress.markClosed(ReportDay.calendar.date(byAdding: .day, value: -1, to: ReportDay.today())!)
                return true
            })
    }
}

@MainActor
@Observable
private final class BackupSampleLegacyFlag { var available = true }

struct BackupSamplesView: View {
    @State private var sample = SyncSamples()
    @State private var showsPhotos = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("로컬 검증 예시 · 서버에 연결하지 않아요")
                        .font(.body2).foregroundStyle(Color.textSecondary)
                }
                BackupSettingsSection(model: sample.model)
                Section {
                    Button("복원한 사진 보기") { showsPhotos = true }
                    Text("합성 자료로 오류·재시도·사진 복원을 확인해요. 실제 계정의 백업 상태가 아니에요.")
                        .font(.caption1).foregroundStyle(Color.textSecondary)
                }
            }
            .navigationTitle("백업 동작 예시")
            .task { await sample.model.retry() }
            .sheet(isPresented: $showsPhotos) { PendingPhotosView(store: sample.photos) }
        }
    }
}

@MainActor
private final class SampleProgress: ProgressSyncServing {
    private var failsFirst = true
    private var state = DayCloseState()
    private var revision: Int64 = 0
    func sync(_ request: ProgressSyncRequest) async throws -> ProgressSyncResponse {
        try await Task.sleep(for: .milliseconds(150))
        if failsFirst { failsFirst = false; throw APIError.invalidResponse }
        if let legacy = request.legacyState { state = try legacy.local() }
        for operation in request.operations { operation.apply(to: &state) }
        revision += 1
        return ProgressSyncResponse(revision: revision, state: RemoteProgressState(state), acknowledgedOperations: request.operations.map(\.id))
    }
}
@MainActor
private struct SamplePhotos: PhotoSyncServing {
    private var photo: SyncedPhoto {
        SyncedPhoto(photoId: ReportSamples.photoID(2), clientId: UUID(uuidString: "40000000-0000-0000-0000-000000000002"),
                    capturedAt: .now.addingTimeInterval(-3600), context: .snack, status: "UPLOADED", confirmed: false, dismissed: false)
    }
    func pendingPage(cursor: String?) async throws -> PhotoSyncPage { PhotoSyncPage(items: [photo], nextCursor: nil) }
    func metadata(_ id: UUID) async throws -> SyncedPhoto { photo }
    func updateMetadata(_ id: UUID, value: PhotoMetadataUpdate) async throws {}
    func dismiss(_ id: UUID) async throws {}
}
#endif
