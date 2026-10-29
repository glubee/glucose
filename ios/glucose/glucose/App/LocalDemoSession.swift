#if DEBUG
import Foundation

/// Only the mode flag persists; sample records live in their isolated preview stores.
@MainActor
@Observable
final class LocalDemoSession {
    static let shared = LocalDemoSession(onTransition: { active in
        AuthSession.shared.invalidatePendingRequests()
        DataSyncCoordinator.shared.invalidate()
        PendingPhotoStore.shared.suspendUploads()
        PhotoViewURLCache.shared.clearAll()
        if !active {
            AuthSession.shared.bootstrap()
            DataSyncCoordinator.shared.bind()
            DataSyncCoordinator.shared.schedule()
        }
    })
    private(set) var isActive: Bool
    private(set) var generation = UUID()
    private let defaults: UserDefaults
    private let onTransition: (Bool) -> Void
    private let key = "local_demo_enabled_v1"
    private var sampleStore: TimelineSamples?
    var samples: TimelineSamples {
        if let sampleStore { return sampleStore }
        let store = TimelineSamples()
        sampleStore = store
        return store
    }

    init(defaults: UserDefaults = .standard, onTransition: @escaping (Bool) -> Void = { _ in }) {
        self.defaults = defaults
        self.onTransition = onTransition
        isActive = defaults.bool(forKey: key)
    }
    func activate(reset: Bool = false) {
        guard !isActive || reset else { return }
        if reset { sampleStore?.photos.removeAll(); sampleStore = nil }
        isActive = true
        defaults.set(true, forKey: key)
        generation = UUID()
        onTransition(true)
    }
    func deactivate() {
        isActive = false
        defaults.set(false, forKey: key)
        generation = UUID()
        onTransition(false)
    }
}
#endif
