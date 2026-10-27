//
//  OnboardingViewModel.swift
//  glucose
//
//  글루비와 대화하며 첫 설정을 하는 흐름 (docs/ios-design-v4.md 0-2장).
//  글루비는 한 번에 한 문장씩 말하고(한 글자씩 찍힘), 사용자는 아래 입력칸으로 답한다.
//

import Foundation
import UserNotifications

struct ChatMessage: Identifiable {
    enum Speaker: Equatable {
        case bee(MascotPose)
        case user
    }

    enum Attachment {
        /// 쓰는 법 3줄 카드
        case howTo
    }

    let id = UUID()
    let speaker: Speaker
    let text: String
    var attachment: Attachment? = nil
    /// 타이핑을 시작한 시각. 건너뛰면 아주 먼 과거로 바꿔 전체를 바로 보여준다
    var startedAt: Date = .now
}

@MainActor
@Observable
final class OnboardingViewModel {

    enum Step: Int, CaseIterable {
        case hello, name, howTo, insulin, dayClose, notifications, widget, signIn
    }

    enum NotificationChoice {
        case undecided, granted, denied
    }

    private struct BeeLine {
        let pose: MascotPose
        let text: String
        var attachment: ChatMessage.Attachment? = nil
    }

    /// 위젯 안내 단계를 보여줄지 (W3에서 위젯이 생겨 켬)
    static let widgetsAvailable = true
    /// 한 글자가 찍히는 간격(초)
    static let characterInterval: Double = 0.045
    /// 한 문장을 다 찍은 뒤 다음 문장으로 넘어가기 전 쉬는 시간(초)
    static let readingPause: Double = 1.0

    private(set) var step: Step = .hello
    private(set) var messages: [ChatMessage] = []
    /// 글루비가 말하는 중에는 입력칸을 숨긴다. 첫 말을 시작하기 전에도 숨겨 둔다
    private(set) var isBeeTalking = true
    private(set) var pose: MascotPose = .flyin

    var nickname: String
    private(set) var insulins: [UsualInsulin]
    var dayClose: Date
    private(set) var notificationChoice: NotificationChoice = .undecided

    /// "동작 줄이기"를 켠 사용자는 타이핑 없이 바로 보여준다
    var reduceMotion = false

    private let preferences: UserPreferences
    private var skipRequested = false

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

    /// 화면에 크게 보이는, 글루비가 지금 하는 말
    var currentLine: ChatMessage? {
        messages.last { if case .bee = $0.speaker { true } else { false } }
    }

    /// 첫 인사와 로그인은 건너뛸 수 없다
    var canSkip: Bool { step != .hello && step != .signIn }

    // MARK: - 시작과 타이핑

    func start() {
        guard messages.isEmpty else { return }
        Task { await say(intro(for: step)) }
    }

    /// 말풍선을 탭하면 지금 말하고 있는 문장들을 바로 끝까지 보여준다
    func skipTyping() {
        guard isBeeTalking else { return }
        skipRequested = true
        for index in messages.indices { messages[index].startedAt = .distantPast }
    }

    static func typingDuration(of text: String) -> Double {
        Double(text.count) * characterInterval
    }

    private func say(_ lines: [BeeLine]) async {
        isBeeTalking = true
        skipRequested = false
        for line in lines {
            pose = line.pose
            let instant = reduceMotion || skipRequested
            messages.append(ChatMessage(speaker: .bee(line.pose), text: line.text, attachment: line.attachment,
                                        startedAt: instant ? .distantPast : .now))
            if !instant {
                // 다 찍힌 뒤 읽을 틈을 둔다(다음 문장이 이 문장을 대신한다). 건너뛰기를 누르면 바로 다음 문장으로
                let deadline = Date.now.addingTimeInterval(Self.typingDuration(of: line.text) + Self.readingPause)
                while Date.now < deadline && !skipRequested {
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        }
        isBeeTalking = false
    }

    /// 사용자 말풍선을 붙이고, 반응 + (advance면) 다음 단계 첫 말을 이어서 한다
    private func answer(_ text: String, then lines: [BeeLine], advance: Bool = true) {
        messages.append(ChatMessage(speaker: .user, text: text, startedAt: .distantPast))
        continueTalking(with: lines, advance: advance)
    }

    private func continueTalking(with lines: [BeeLine], advance: Bool = true) {
        var next = lines
        if advance, let following = nextStep() {
            persist()
            step = following
            next += intro(for: following)
        }
        Task { await say(next) }
    }

    private func nextStep() -> Step? {
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return nil }
        return steps[index + 1]
    }

    // MARK: - 단계별 글루비 첫 말

    private func intro(for step: Step) -> [BeeLine] {
        switch step {
        case .hello:
            [BeeLine(pose: .flyin, text: "안녕하세요! 저는 글루비예요."),
             BeeLine(pose: .wave, text: "하루를 같이 모으는 꿀벌이에요.")]
        case .name:
            [BeeLine(pose: .curious, text: "뭐라고 불러드릴까요?")]
        case .howTo:
            [BeeLine(pose: .camera, text: "쓰는 법은 간단해요."),
             BeeLine(pose: .camera, text: "먹을 때 한 번, 맞을 때 한 번. 나머지는 밤에 같이 해요.", attachment: .howTo)]
        case .insulin:
            [BeeLine(pose: .think, text: "평소에 쓰는 인슐린을 알려주세요."),
             BeeLine(pose: .think, text: "제가 정하거나 추천하지 않고, 입력하신 값을 그대로 채워둘게요.")]
        case .dayClose:
            [BeeLine(pose: .clock, text: "하루 마무리는 몇 시가 좋아요?")]
        case .notifications:
            [BeeLine(pose: .cheer, text: "기록할 때를 알림으로 챙겨드릴까요?"),
             BeeLine(pose: .cheer, text: "하루 두 번까지만, 밤에는 조용히 있을게요.")]
        case .widget:
            [BeeLine(pose: .point, text: "홈 화면에 저를 붙여두면 한 번에 기록돼요.")]
        case .signIn:
            [BeeLine(pose: .honeypot, text: "마지막이에요. 기록을 안전하게 보관할게요.")]
        }
    }

    // MARK: - 사용자 답

    func startChatting() {
        answer("좋아요!", then: [])
    }

    func submitName() {
        let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        nickname = name
        answer(Self.introduceName(name), then: [BeeLine(pose: .nod, text: "\(name)님! 예쁜 이름이네요.")])
    }

    func acknowledgeHowTo() {
        answer("알겠어요", then: [])
    }

    func addInsulin(name: String, units: Double?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        insulins.append(UsualInsulin(name: trimmed, units: units))
        let detail = units.map { " · 평소 \($0.formatted(.number.precision(.fractionLength(0...1))))U" } ?? ""
        answer(trimmed + detail, then: [BeeLine(pose: .thumbsup, text: "기억해둘게요. 더 있으면 알려주세요.")],
               advance: false)
    }

    func finishInsulins() {
        answer("다 했어요", then: [BeeLine(pose: .nod, text: "맞을 때 바로 채워드릴게요.")])
    }

    func submitDayClose() {
        let time = timeText(dayClose)
        answer("\(time)에 할게요", then: [BeeLine(pose: .clock, text: "\(time)에 꿀통 들고 찾아갈게요.")])
    }

    func requestNotifications() async {
        messages.append(ChatMessage(speaker: .user, text: "알림 받을게요", startedAt: .distantPast))
        // 시스템 권한 창이 떠 있는 동안 입력칸을 숨겨 두 번 누르지 않게 한다
        isBeeTalking = true
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        notificationChoice = granted ? .granted : .denied
        let reaction = granted
            ? BeeLine(pose: .cheer, text: "약속해요! 잊을 때쯤 찾아갈게요.")
            : BeeLine(pose: .nod, text: "괜찮아요. 설정에서 언제든 불러주세요.")
        continueTalking(with: [reaction])
    }

    func declineNotifications() {
        notificationChoice = .denied
        answer("괜찮아요", then: [BeeLine(pose: .nod, text: "알겠어요. 설정에서 언제든 불러주세요.")])
    }

    func acknowledgeWidget() {
        answer("알겠어요", then: [])
    }

    /// "나중에"를 누르면 그 단계를 건너뛴다
    func skip() {
        answer("나중에 할게요", then: [BeeLine(pose: .nod, text: "괜찮아요. 설정에서 언제든 바꿀 수 있어요.")])
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
        preferences.dayCloseTime = Calendar.current.dateComponents([.hour, .minute], from: dayClose)
    }

    /// "민지예요" / "지민이에요" — 마지막 글자 받침에 따라 고른다
    static func introduceName(_ name: String) -> String {
        guard let last = name.unicodeScalars.last, (0xAC00...0xD7A3).contains(last.value) else {
            return name
        }
        let hasFinalConsonant = (last.value - 0xAC00) % 28 != 0
        return name + (hasFinalConsonant ? "이에요" : "예요")
    }
}
