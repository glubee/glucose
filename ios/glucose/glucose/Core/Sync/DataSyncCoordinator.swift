import Foundation

@MainActor
protocol ProgressSyncServing { func sync(_ request: ProgressSyncRequest) async throws -> ProgressSyncResponse }
@MainActor
struct ProgressSyncService: ProgressSyncServing {
    var sessionGeneration: UUID? = nil
    func sync(_ request: ProgressSyncRequest) async throws -> ProgressSyncResponse {
        try await APIClient.shared.send(path: "/v1/progress/sync", method: .post, body: request, expectedSession: sessionGeneration)
    }
}

enum BackupStatus: Equatable { case idle, working, waiting, saved, failed }

@MainActor
@Observable
final class DataSyncCoordinator {
    static let shared = DataSyncCoordinator()
    private(set) var status: BackupStatus = .idle
    private let progress: DayCloseStore
    private let photos: PendingPhotoStore
    private let progressService: ProgressSyncServing?
    private let photoService: PhotoSyncServing?
    private let currentAccount: () -> UUID?
    private let isEnabled: () -> Bool
    private var generation = UUID()
    private var activeTask: Task<Void, Never>?

    init(progress: DayCloseStore? = nil, photos: PendingPhotoStore? = nil,
         progressService: ProgressSyncServing? = nil, photoService: PhotoSyncServing? = nil,
         currentAccount: (() -> UUID?)? = nil, isEnabled: (() -> Bool)? = nil) {
        self.progress = progress ?? .shared; self.photos = photos ?? .shared
        self.progressService = progressService; self.photoService = photoService
        self.currentAccount = currentAccount ?? { AuthSession.shared.accountID }
        self.isEnabled = isEnabled ?? { AuthSession.shared.isAuthenticated && !RecordDataSource.isPreview }
    }
    func bind() {
        progress.onMutation = { [weak self] in self?.schedule() }
        photos.onSyncNeeded = { [weak self] in self?.schedule() }
    }
    func schedule() { Task { await refresh() } }
    func invalidate() { generation = UUID(); activeTask?.cancel(); activeTask = nil; status = .idle }
    func refresh() async {
        guard let owner = currentAccount(), isEnabled() else { return }
        if let activeTask { await activeTask.value; return }
        let scope = generation
        let task = Task { [self] in
            await performRefresh(owner: owner, scope: scope)
            if generation == scope { activeTask = nil }
        }
        activeTask = task
        await task.value
    }

    private func check(owner: UUID, scope: UUID) throws {
        try Task.checkCancellation()
        guard generation == scope, currentAccount() == owner, isEnabled() else { throw CancellationError() }
    }

    private func performRefresh(owner: UUID, scope: UUID) async {
        status = .working
        let progressAPI = progressService ?? ProgressSyncService(sessionGeneration: AuthSession.shared.generation)
        let photoAPI = photoService ?? PhotoSyncService(sessionGeneration: AuthSession.shared.generation)
        var failed = false
        do {
            for batch in 0..<64 {
                try check(owner: owner, scope: scope)
                let request = progress.makeSyncRequest()
                let response = try await progressAPI.sync(request)
                try check(owner: owner, scope: scope)
                try progress.applyServer(response, for: request)
                if !progress.hasPendingChanges { break }
                // Missing ACKs or a repeatedly older revision must not spin forever.
                let next = progress.makeSyncRequest()
                guard batch < 63, request.operations != next.operations || request.legacyState != next.legacyState
                else { throw APIError.invalidResponse }
            }
        } catch is CancellationError {
            if generation == scope { status = .idle }
            return
        }
        catch { failed = true }
        do {
            try check(owner: owner, scope: scope)
            await photos.uploadPending()
            try check(owner: owner, scope: scope)
            try await photos.synchronize(using: photoAPI)
            try check(owner: owner, scope: scope)
        } catch is CancellationError {
            if generation == scope { status = .idle }
            return
        }
        catch { failed = true }
        guard (try? check(owner: owner, scope: scope)) != nil else { return }
        status = failed ? .failed : (progress.hasPendingChanges || photos.hasPendingBackup ? .waiting : .saved)
    }
}
