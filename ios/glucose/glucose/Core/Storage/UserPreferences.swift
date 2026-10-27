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

/// 글루비 말투. 매운 맛만 "화남" 문구를 쓴다
enum NagTone: String, Codable, CaseIterable {
    case gentle, normal, spicy

    var title: String {
        switch self {
        case .gentle: "순한 맛"
        case .normal: "보통"
        case .spicy: "매운 맛"
        }
    }
}

@Observable
final class UserPreferences {

    static let shared = UserPreferences()

    private struct Stored: Codable {
        var nickname = ""
        var usualInsulins: [UsualInsulin] = []
        var dayCloseHour = 21
        var dayCloseMinute = 0
        var nagTone: NagTone = .normal
        var onboardingCompleted = false
    }

    private let defaults: UserDefaults
    private let key = "user_preferences_v1"
    private var stored: Stored {
        didSet { save() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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

    var nagTone: NagTone {
        get { stored.nagTone }
        set { stored.nagTone = newValue }
    }

    var onboardingCompleted: Bool {
        get { stored.onboardingCompleted }
        set { stored.onboardingCompleted = newValue }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: key)
    }
}
