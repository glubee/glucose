import Foundation
import UserNotifications

/// JWT subject chooses a local namespace only; the server still validates every request.
enum AccountIdentity {
    static func userID(in token: String) -> UUID? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let bytes = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let subject = json["sub"] as? String else { return nil }
        return UUID(uuidString: subject)
    }
}

@MainActor
enum AccountDataCoordinator {
    static func activate(_ id: UUID?, allowLegacy: Bool = false) {
        DataSyncCoordinator.shared.invalidate()
        NudgeScheduler.invalidate()
        PhotoViewURLCache.shared.clearAll()
        PendingPhotoStore.shared.activateAccount(id, allowLegacy: allowLegacy)
        DayCloseStore.shared.activateAccount(id, allowLegacy: allowLegacy)
        UserPreferences.shared.activateAccount(id, allowLegacy: allowLegacy)
        DataSyncCoordinator.shared.bind()
        WidgetSnapshot.erase()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
    static var hasUnclaimedLegacy: Bool {
        DayCloseStore.shared.hasUnclaimedLegacy || UserPreferences.shared.hasUnclaimedLegacy || PendingPhotoStore.shared.hasUnclaimedLegacy
    }
    static func claimLegacy() {
        DayCloseStore.shared.claimLegacyForActiveAccount()
        UserPreferences.shared.claimLegacyForActiveAccount()
        PendingPhotoStore.shared.claimLegacyForActiveAccount()
        DataSyncCoordinator.shared.schedule()
    }
}

/// The first upgrade launch decides whether old unscoped data has a known owner.
enum LegacyDataOwnership {
    static func initialOwner(in defaults: UserDefaults, cachedAccount: UUID?) -> UUID? {
        let key = "legacy_upgrade_owner_v1"
        if let recorded = defaults.string(forKey: key) { return UUID(uuidString: recorded) }
        defaults.set(cachedAccount?.uuidString ?? "unattributed", forKey: key)
        return cachedAccount
    }
}
