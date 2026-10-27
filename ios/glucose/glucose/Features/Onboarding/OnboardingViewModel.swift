//
//  OnboardingViewModel.swift
//  glucose
//
//  글루비와 대화하며 첫 설정을 하는 흐름 (docs/ios-design-v4.md 0-2장).
//  각 단계에서 글루비의 동작·말은 사용자가 고른 값에 따라 바뀐다.
//

import Foundation
import UserNotifications

@Observable
final class OnboardingViewModel {

    enum Step: Int, CaseIterable {
        case hello, name, howTo, insulin, dayClose, notifications, widget, signIn
    }

    enum NotificationChoice {
        case undecided, granted, denied
    }

    /// 위젯(W3)이 생기기 전에는 위젯 안내 단계를 건너뛴다
    static let widgetsAvailable = false

    private(set) var step: Step = .hello
    var nickname: String
    var insulins: [UsualInsulin]
    var dayClose: Date
    private(set) var notificationChoice: NotificationChoice = .undecided

    /// 이름을 확정했을 때처럼 한 번 반응하는 말
    private(set) var reaction: String?

    private let preferences: UserPreferences
    private let calendar = Calendar.current

    init(preferences: UserPreferences = .shared) {
        self.preferences = preferences
        nickname = preferences.nickname
        insulins = preferences.usualInsulins
        let time = preferences.dayCloseTime
        dayClose = Calendar.current.date(bySettingHour: time.hour ?? 21, minute: time.minute ?? 0,
                                         second: 0, of: .now) ?? .now
        #if DEBUG
        // 시뮬레이터 확인용: 실행 인자 -onboardingStep <번호>
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-onboardingStep"), index + 1 < arguments.count,
           let raw = Int(arguments[index + 1]), let debugStep = Step(rawValue: raw) {
            step = debugStep
        }
        #endif
    }

    var steps: [Step] {
        Step.allCases.filter { $0 != .widget || Self.widgetsAvailable }
    }

    var progress: Double {
        guard let index = steps.firstIndex(of: step) else { return 0 }
        return Double(index + 1) / Double(steps.count)
    }

    var canGoBack: Bool { step != steps.first }
    /// 첫 인사와 로그인은 건너뛸 수 없다
    var canSkip: Bool { step != .hello && step != .signIn }

    var beePose: MascotPose {
        switch step {
        case .hello: .flyin
        case .name: nickname.isEmpty ? .curious : .nod
        case .howTo: .camera
        case .insulin: insulins.isEmpty ? .think : .thumbsup
        case .dayClose: .clock
        case .notifications:
            notificationChoice == .denied ? .nod : .cheer
        case .widget: .point
        case .signIn: .honeypot
        }
    }

    var beeLine: String {
        if let reaction { return reaction }
        switch step {
        case .hello:
            return "안녕하세요! 저는 글루비예요.\n하루를 같이 모으는 꿀벌이에요."
        case .name:
            return "뭐라고 불러드릴까요?"
        case .howTo:
            return "먹을 때 한 번, 맞을 때 한 번.\n나머지는 밤에 같이 해요."
        case .insulin:
            return insulins.isEmpty ? "평소에 쓰는 인슐린을 알려주세요." : "기억해둘게요. 맞을 때 바로 채워드릴게요."
        case .dayClose:
            return "\(timeText(dayClose))에 꿀통 들고 찾아갈게요."
        case .notifications:
            switch notificationChoice {
            case .undecided: return "기록할 때를 알림으로 챙겨드릴까요?"
            case .granted: return "약속해요! 잊을 때쯤 찾아갈게요."
            case .denied: return "괜찮아요. 설정에서 언제든 불러주세요."
            }
        case .widget:
            return "여기 저를 붙여두면 한 번에 기록돼요."
        case .signIn:
            return "마지막이에요. 기록을 안전하게 보관할게요."
        }
    }

    func next() {
        persist()
        reaction = nil
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return }
        step = steps[index + 1]
    }

    func back() {
        reaction = nil
        guard let index = steps.firstIndex(of: step), index > 0 else { return }
        step = steps[index - 1]
    }

    func commitName() {
        nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        reaction = nickname.isEmpty ? nil : "\(nickname)님! 예쁜 이름이네요."
    }

    func addInsulin(name: String, units: Double?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        insulins.append(UsualInsulin(name: trimmed, units: units))
        reaction = nil
    }

    func removeInsulin(_ insulin: UsualInsulin) {
        insulins.removeAll { $0.id == insulin.id }
    }

    func requestNotifications() async {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        notificationChoice = granted ? .granted : .denied
    }

    /// 로그인까지 끝났을 때 부른다
    func finish() {
        persist()
        preferences.onboardingCompleted = true
    }

    func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "ko_KR")))
    }

    private func persist() {
        preferences.nickname = nickname
        preferences.usualInsulins = insulins
        preferences.dayCloseTime = calendar.dateComponents([.hour, .minute], from: dayClose)
    }
}
