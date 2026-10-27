//
//  QuickRecordShortcuts.swift
//  glucose
//
//  Siri·단축어·동작 버튼에서 위젯과 같은 화면을 연다. 앱을 열어 DeepLinkRouter로 넘길 뿐이다.
//

import AppIntents

struct OpenQuickCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "사진 찍기"
    static let description = IntentDescription("글루비 카메라를 바로 열어요.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkRouter.shared.handle(URL(string: "glubee://capture")!)
        return .result()
    }
}

struct OpenInsulinConfirmIntent: AppIntent {
    static let title: LocalizedStringResource = "인슐린 기록"
    static let description = IntentDescription("인슐린 투여 확인을 바로 열어요.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkRouter.shared.handle(URL(string: "glubee://insulin")!)
        return .result()
    }
}

struct QuickRecordShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenQuickCaptureIntent(),
            phrases: ["\(.applicationName)로 사진 찍기", "\(.applicationName) 사진 기록"],
            shortTitle: "사진 찍기",
            systemImageName: "camera.fill"
        )
        AppShortcut(
            intent: OpenInsulinConfirmIntent(),
            phrases: ["\(.applicationName)로 인슐린 기록", "\(.applicationName) 인슐린 맞았어"],
            shortTitle: "인슐린 기록",
            systemImageName: "syringe.fill"
        )
    }
}
