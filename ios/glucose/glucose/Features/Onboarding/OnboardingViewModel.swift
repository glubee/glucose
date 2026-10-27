//
//  OnboardingViewModel.swift
//  glucose
//
//  글루비와 함께하는 첫 설정 8단계 — 디자이너 v5 프로토타입 그대로.
//  단계마다: 글루비 동작·움직임 → 큰 문장이 한 글자씩 → 다 찍히면 아래에서 입력칸이 올라온다.
//  버튼을 누르면 글루비가 짧게 반응한 뒤 다음 단계로 간다.
//

import Foundation
import UserNotifications

@MainActor
@Observable
final class OnboardingViewModel {

    enum Step: Int, CaseIterable {
        case hello, name, howTo, insulin, dayClose, notifications, widget, signIn
    }

    enum NotificationChoice {
        case undecided, granted, denied
    }

    private(set) var step: Step = .hello
    /// 지금 찍히는 문장. 바뀌면 처음부터 다시 찍힌다
    private(set) var line = ""
    private(set) var pose: MascotPose = .flyin
    private(set) var motion: MascotMotion = .flyIn
    /// 문장을 다 찍으면 아래 입력칸이 올라온다
    private(set) var isPanelUp = false
    /// 반응 문장을 말하는 동안에는 버튼을 막는다
    private(set) var isReacting = false

    var nickname: String
    private(set) var insulins: [UsualInsulin]
    var insulinName = ""
    var insulinUnits = ""
    /// 하루 마무리 시각(자정부터 분)
    private(set) var dayCloseMinutes: Int
    private(set) var notificationChoice: NotificationChoice = .undecided
    /// 쓰는 법 3줄 중 고른 것(글루비 동작이 바뀐다)
    private(set) var howToSelection: Int?

    private let preferences: UserPreferences
    private var nameTask: Task<Void, Never>?

    init(preferences: UserPreferences = .shared) {
        self.preferences = preferences
        nickname = preferences.nickname
        insulins = preferences.usualInsulins
        let time = preferences.dayCloseTime
        dayCloseMinutes = (time.hour ?? 21) * 60 + (time.minute ?? 0)
        #if DEBUG
        // 시뮬레이터 확인용: 실행 인자 -onboardingStep <번호>
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-onboardingStep"), index + 1 < arguments.count,
           let raw = Int(arguments[index + 1]), let debugStep = Step(rawValue: raw) {
            step = debugStep
        }
        #endif
        show(step)
    }

    var progressIndex: Int { step.rawValue }
    var stepCount: Int { Step.allCases.count }
    var showsLater: Bool { step != .signIn }

    var primaryTitle: String {
        switch step {
        case .hello: "반가워요"
        case .name: "좋아요"
        case .howTo: "다음"
        case .insulin: "저장하기"
        case .dayClose: "이 시간으로 할게요"
        case .notifications: "알림 켜기"
        case .widget: "다 했어요"
        case .signIn: "Apple로 로그인"
        }
    }

    // MARK: - 단계 보여주기

    private func show(_ step: Step) {
        self.step = step
        isPanelUp = false
        isReacting = false
        howToSelection = nil
        switch step {
        case .hello: say("안녕하세요! 저는 글루비예요.\n하루를 같이 모으는 꿀벌이에요.", .flyin, .flyIn)
        case .name: say("뭐라고 불러드릴까요?", .curious)
        case .howTo: say("먹을 때 한 번, 맞을 때 한 번.\n나머지는 밤에 같이 해요.", .camera)
        case .insulin: say("평소 쓰는 인슐린을 알려주세요.", .note)
        case .dayClose: say("하루 마무리는 몇 시에 할까요?", .clock)
        case .notifications: say("마무리 시간에 한 번만\n알려드려도 될까요?", .cheer)
        case .widget: say("여기 저를 붙여두면\n한 번에 기록돼요.", .pointLeft)
        case .signIn: say("기록을 안전하게 보관할게요.", .honeypot)
        }
    }

    private func say(_ text: String, _ pose: MascotPose, _ motion: MascotMotion = .pop) {
        line = text
        self.pose = pose
        self.motion = motion
    }

    /// 문장이 다 찍혔을 때(TypingText가 부른다)
    func lineFinished() {
        guard !isReacting, !isPanelUp else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            isPanelUp = true
        }
    }

    /// 반응 문장을 말하고 잠시 뒤 다음 단계로
    private func react(_ text: String, _ pose: MascotPose, _ motion: MascotMotion, then delay: Duration) async {
        isReacting = true
        say(text, pose, motion)
        try? await Task.sleep(for: delay)
        advance()
    }

    private func advance() {
        persist()
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        show(next)
    }

    // MARK: - 버튼

    func primary() async {
        guard !isReacting else { return }
        switch step {
        case .hello, .howTo, .widget:
            advance()
        case .name:
            let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            nickname = name
            guard !name.isEmpty else { return advance() }
            await react("\(name)님! 예쁜 이름이네요.", .cheer, .jump, then: .milliseconds(1500))
        case .insulin:
            addInsulin()
            await react("기억해둘게요. 맞을 때 바로 채워드릴게요.", .nod, .pop, then: .milliseconds(1900))
        case .dayClose:
            await react("그 시간에 꿀통 들고 찾아갈게요.", .honeypot, .pop, then: .milliseconds(1600))
        case .notifications:
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            notificationChoice = granted ? .granted : .denied
            if granted {
                await react("약속해요!", .cheer, .jump, then: .milliseconds(1100))
            } else {
                await react("괜찮아요. 설정에서 언제든 불러주세요.", .nod, .pop, then: .milliseconds(1900))
            }
        case .signIn:
            break // 로그인 버튼이 따로 처리한다
        }
    }

    func later() async {
        guard !isReacting else { return }
        if step == .notifications {
            notificationChoice = .denied
            await react("괜찮아요. 설정에서 언제든 불러주세요.", .nod, .pop, then: .milliseconds(1900))
        } else {
            advance()
        }
    }

    // MARK: - 단계별 입력

    /// 이름을 치다 멈추면(0.5초) 글루비가 이름을 불러준다
    func nicknameChanged() {
        nameTask?.cancel()
        nameTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                say("뭐라고 불러드릴까요?", .curious)
            } else {
                say("\(name)님! 예쁜 이름이네요.", .cheer, .jump)
            }
        }
    }

    func selectHowTo(_ index: Int) {
        howToSelection = index
        let looks: [MascotPose] = [.camera, .thumbsup, .magnifier]
        pose = looks[index]
        motion = .pop
    }

    /// 입력칸의 값을 평소 인슐린으로 추가한다(앱이 정하거나 추천하지 않는다)
    func addInsulin() {
        let name = insulinName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        insulins.append(UsualInsulin(name: name, units: Double(insulinUnits.replacingOccurrences(of: ",", with: "."))))
        insulinName = ""
        insulinUnits = ""
    }

    func shiftDayClose(byMinutes minutes: Int) {
        dayCloseMinutes = (dayCloseMinutes + minutes + 1440) % 1440
    }

    static func timeText(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// 로그인까지 끝났을 때 부른다
    func finish() {
        persist()
        preferences.onboardingCompleted = true
        Task { await NudgeScheduler.refresh(preferences: preferences) }
    }

    private func persist() {
        preferences.nickname = nickname
        preferences.usualInsulins = insulins
        preferences.dayCloseTime = DateComponents(hour: dayCloseMinutes / 60, minute: dayCloseMinutes % 60)
    }
}
