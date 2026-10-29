//
//  UserPreferences.swift
//  glucose
//
//  온보딩·설정에서 정한 값. 서버 프로필 API가 생기기 전까지 기기에만 저장한다.
//  혈당·토큰 같은 민감한 값은 여기에 두지 않는다.
//

import Foundation

/// 사용자가 직접 입력한 "평소 인슐린". 앱이 계산하거나 추천한 값이 아니다.
struct UsualInsulin: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// 평소 단위. 매번 다르면 비워둔다
    var units: Double?
}

@Observable
final class UserPreferences {

    static let shared = UserPreferences(accountScoped: true)

    private struct Stored: Codable {
        var nickname = ""
        var usualInsulins: [UsualInsulin] = []
        var dayCloseHour = 21
        var dayCloseMinute = 0
        var onboardingCompleted = false
    }

    private let defaults: UserDefaults
    private var key = "user_preferences_v1"
    private let accountScoped: Bool
    private var accountID: UUID?
    private var stored = Stored() {
        didSet { save() }
    }

    init(defaults: UserDefaults = .standard, accountScoped: Bool = false) {
        self.accountScoped = accountScoped
        self.defaults = defaults
        if accountScoped { key = "user_preferences_v2.onboarding" }
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Stored.self, from: data) {
            stored = decoded
        } else {
            stored = Stored()
        }
    }

    var nickname: String {
        get { stored.nickname }
        set { stored.nickname = newValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    var usualInsulins: [UsualInsulin] {
        get { stored.usualInsulins }
        set { stored.usualInsulins = newValue }
    }

    var dayCloseTime: DateComponents {
        get { DateComponents(hour: stored.dayCloseHour, minute: stored.dayCloseMinute) }
        set {
            stored.dayCloseHour = newValue.hour ?? 21
            stored.dayCloseMinute = newValue.minute ?? 0
        }
    }

    var onboardingCompleted: Bool {
        get {
            if !accountScoped { return stored.onboardingCompleted }
            if defaults.object(forKey: "onboarding_completed_v2") != nil { return defaults.bool(forKey: "onboarding_completed_v2") }
            guard let data = defaults.data(forKey: "user_preferences_v1"),
                  let legacy = try? JSONDecoder().decode(Stored.self, from: data) else { return false }
            return legacy.onboardingCompleted
        }
        set {
            if accountScoped { defaults.set(newValue, forKey: "onboarding_completed_v2") }
            else { stored.onboardingCompleted = newValue }
        }
    }

    var hasUnclaimedLegacy: Bool {
        defaults.data(forKey: "user_preferences_v1") != nil && defaults.string(forKey: "preferences_legacy_owner") == nil
    }

    func activateAccount(_ id: UUID?, allowLegacy: Bool = false) {
        guard accountScoped else { return }
        accountID = id
        let onboardingData = defaults.data(forKey: "user_preferences_v2.onboarding")
        key = "user_preferences_v2.\(id?.uuidString ?? "onboarding")"
        let data = defaults.data(forKey: key)
        stored = data.flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
        if id != nil, data == nil, let onboardingData,
           let staged = try? JSONDecoder().decode(Stored.self, from: onboardingData) {
            stored = staged
            defaults.removeObject(forKey: "user_preferences_v2.onboarding")
        }
        if allowLegacy { claimLegacyForActiveAccount() }
        save()
    }

    @discardableResult func claimLegacyForActiveAccount() -> Bool {
        guard let accountID, hasUnclaimedLegacy,
              let data = defaults.data(forKey: "user_preferences_v1"),
              let legacy = try? JSONDecoder().decode(Stored.self, from: data) else { return false }
        if stored.nickname.isEmpty { stored.nickname = legacy.nickname }
        if stored.usualInsulins.isEmpty { stored.usualInsulins = legacy.usualInsulins }
        stored.dayCloseHour = legacy.dayCloseHour; stored.dayCloseMinute = legacy.dayCloseMinute
        defaults.set(accountID.uuidString, forKey: "preferences_legacy_owner")
        return true
    }

    func reset() {
        stored = Stored()
        if accountScoped { defaults.set(false, forKey: "onboarding_completed_v2") }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: key)
    }
}

#if DEBUG
extension UserPreferences {
    /// 시뮬레이터 확인용. 실제 저장소를 건드리지 않는다
    static let debugSample: UserPreferences = {
        let preferences = UserPreferences(defaults: UserDefaults(suiteName: "debug-sample") ?? .standard)
        preferences.usualInsulins = [
            UsualInsulin(name: "초속효성 인슐린", units: 4),
            UsualInsulin(name: "기저 인슐린", units: nil),
        ]
        return preferences
    }()
}
#endif
