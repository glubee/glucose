#if DEBUG
import Foundation

/// Only the mode flag persists; sample records live in their isolated preview stores.
@MainActor
@Observable
final class LocalDemoSession {
    static let shared = LocalDemoSession()
    private(set) var isActive: Bool
    private(set) var generation = UUID()
    private let defaults: UserDefaults
    private let key = "local_demo_enabled_v1"
    private var sampleStore: TimelineSamples?
    var samples: TimelineSamples {
        if let sampleStore { return sampleStore }
        let store = TimelineSamples()
        sampleStore = store
        return store
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isActive = defaults.bool(forKey: key)
    }
    func activate(reset: Bool = false) {
        guard !isActive || reset else { return }
        if reset { sampleStore?.photos.removeAll(); sampleStore = nil }
        isActive = true
        defaults.set(true, forKey: key)
        generation = UUID()
    }
    func deactivate() {
        isActive = false
        defaults.set(false, forKey: key)
        generation = UUID()
    }
}
#endif
