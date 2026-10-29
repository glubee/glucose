import Foundation

@MainActor
@Observable
final class BackupSettingsModel {
    static let shared = BackupSettingsModel()
    let coordinator: DataSyncCoordinator
    let progress: DayCloseStore
    let photos: PendingPhotoStore
    let isExample: Bool
    private let canSyncProvider: () -> Bool
    private let legacyProvider: () -> Bool
    private let importAction: () -> Bool
    private(set) var importMessage: String?

    init(coordinator: DataSyncCoordinator? = nil, progress: DayCloseStore? = nil, photos: PendingPhotoStore? = nil,
         isExample: Bool = false, canSync: (() -> Bool)? = nil,
         hasLegacy: (() -> Bool)? = nil, importAction: (() -> Bool)? = nil) {
        self.coordinator = coordinator ?? .shared; self.progress = progress ?? .shared; self.photos = photos ?? .shared
        self.isExample = isExample
        self.canSyncProvider = canSync ?? { AuthSession.shared.isAuthenticated && AuthSession.shared.accountID != nil && !RecordDataSource.isPreview }
        self.legacyProvider = hasLegacy ?? { AccountDataCoordinator.hasUnclaimedLegacy }
        self.importAction = importAction ?? { AccountDataCoordinator.claimLegacy(); return !AccountDataCoordinator.hasUnclaimedLegacy }
    }
    var canSync: Bool { canSyncProvider() }
    var hasLegacy: Bool { legacyProvider() }
    var isWorking: Bool { coordinator.status == .working || photos.isUploading }
    var hasPending: Bool { progress.hasPendingChanges || photos.hasPendingBackup }
    var headline: String {
        guard canSync else { return "로그인하면 백업을 이어갈 수 있어요" }
        if isWorking { return "백업 상태를 확인하고 있어요" }
        if coordinator.status == .failed { return "백업 연결을 확인하지 못했어요" }
        if hasPending { return "이 기기에 먼저 보관했어요" }
        if coordinator.status == .saved { return isExample ? "로컬 검증을 마쳤어요" : "이 계정에 백업했어요" }
        return "백업 상태를 확인해 주세요"
    }
    func retry() async {
        guard canSync, !isWorking else { return }
        await coordinator.refresh()
    }
    func importLegacy() {
        guard canSync, !isWorking else { return }
        guard hasLegacy else { importMessage = "가져올 이전 자료가 없어요."; return }
        importMessage = importAction()
            ? "이전 기기 기록을 가져왔어요. 백업 상태를 확인해 주세요."
            : "일부 자료를 가져오지 못했어요. 가져오지 못한 원본은 기기에 남아 있어요."
        coordinator.schedule()
    }
}
