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


/// 끼니 알림 하나. 시각에 앞뒤 2시간 안 기록이 있으면 그날은 보내지 않는다
struct MealReminder: Codable, Hashable, Identifiable {
    enum Meal: String, Codable, CaseIterable { case breakfast, lunch, dinner }

    var meal: Meal
    var hour: Int
    var minute: Int
    var isOn: Bool

    var id: Meal { meal }

    var name: String {
        switch meal {
        case .breakfast: "아침"
        case .lunch: "점심"
        case .dinner: "저녁"
        }
    }

    static let defaults: [MealReminder] = [
        MealReminder(meal: .breakfast, hour: 8, minute: 30, isOn: true),
        MealReminder(meal: .lunch, hour: 12, minute: 30, isOn: true),
        MealReminder(meal: .dinner, hour: 18, minute: 30, isOn: true),
    ]
}

@Observable
final class UserPreferences {

    static let shared = UserPreferences()

    private struct Stored: Codable {
        var nickname = ""
        var usualInsulins: [UsualInsulin] = []
        var dayCloseHour = 21
        var dayCloseMinute = 0
        var onboardingCompleted = false
        /// 나중에 더한 값은 옵셔널: 예전 저장값을 읽을 때 없어도 전체가 초기화되지 않게
        var mealReminders: [MealReminder]?
        var pendingPhotoReminder: Bool?
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

    var onboardingCompleted: Bool {
        get { stored.onboardingCompleted }
        set { stored.onboardingCompleted = newValue }
    }

    /// 끼니 알림(아침·점심·저녁). 기본 켜짐 8:30 / 12:30 / 18:30
    var mealReminders: [MealReminder] {
        get { stored.mealReminders ?? MealReminder.defaults }
        set { stored.mealReminders = newValue }
    }

    /// 마무리 1시간 전, 확인 안 한 사진이 있을 때만. 기본 켜짐
    var pendingPhotoReminder: Bool {
        get { stored.pendingPhotoReminder ?? true }
        set { stored.pendingPhotoReminder = newValue }
    }

    /// 계정을 지웠을 때: 처음 설치한 상태로(온보딩부터 다시)
    func reset() {
        stored = Stored()
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
