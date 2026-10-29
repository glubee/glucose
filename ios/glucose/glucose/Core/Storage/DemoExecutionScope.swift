#if DEBUG
import Foundation

/// Fence a development-only server job across logout/account or demo-mode changes.
@MainActor
struct DemoExecutionScope {
    private let token = AuthSession.shared.accessToken
    private let modeGeneration = LocalDemoSession.shared.generation
    var isCurrent: Bool {
        !Task.isCancelled && token != nil && token == AuthSession.shared.accessToken
            && modeGeneration == LocalDemoSession.shared.generation && !LocalDemoSession.shared.isActive
    }
}
#endif
