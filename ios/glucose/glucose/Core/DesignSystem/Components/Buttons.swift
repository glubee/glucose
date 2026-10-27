//
//  Buttons.swift
//  glucose
//
//  v5 버튼. 기본 버튼은 라이트에서 어두운 바탕, 다크에서 밝은 바탕으로 뒤집힌다.
//  노랑(accent)은 화면당 한 곳에만(예: 홈의 "음식 찍기").
//  사용: Button("기록 저장") { … }.buttonStyle(.glubeePrimary)
//

import SwiftUI

struct GlubeeButtonStyle: ButtonStyle {
    enum Kind {
        /// 어두운 캡슐(다크 모드에선 밝은 캡슐). 기본 동작
        case primary
        /// 노랑 캡슐. 화면당 한 곳만
        case accent
        /// 테두리 캡슐. "아니에요", "취소"
        case secondary
        /// 회색 캡슐. 아직 끝낼 수 없는 단계의 마무리 버튼 등
        case muted
        /// 회색 바탕 + 진한 글씨(홈의 "인슐린")
        case soft
    }

    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline2)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: Metrics.buttonHeight)
            .padding(.horizontal, Spacing.m)
            .background(background, in: Capsule())
            .overlay {
                if kind == .secondary {
                    Capsule().strokeBorder(Color.line, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: .onButton
        case .accent: .onBrand
        case .secondary: .textPrimary
        case .muted: .textSecondary
        case .soft: .textPrimary
        }
    }

    private var background: Color {
        switch kind {
        case .primary: .buttonFill
        case .accent: .brand
        case .secondary: .canvas
        case .muted, .soft: .surfaceMuted
        }
    }
}

extension ButtonStyle where Self == GlubeeButtonStyle {
    static var glubeePrimary: GlubeeButtonStyle { GlubeeButtonStyle(kind: .primary) }
    static var glubeeAccent: GlubeeButtonStyle { GlubeeButtonStyle(kind: .accent) }
    static var glubeeSecondary: GlubeeButtonStyle { GlubeeButtonStyle(kind: .secondary) }
    static var glubeeMuted: GlubeeButtonStyle { GlubeeButtonStyle(kind: .muted) }
    static var glubeeSoft: GlubeeButtonStyle { GlubeeButtonStyle(kind: .soft) }
}

#Preview {
    VStack(spacing: Spacing.s) {
        Button("기록 저장") {}.buttonStyle(.glubeePrimary)
        Button("음식 찍기") {}.buttonStyle(.glubeeAccent)
        Button("아니에요") {}.buttonStyle(.glubeeSecondary)
        Button("오늘 정리 마치기") {}.buttonStyle(.glubeeMuted)
        Button("기록 저장") {}.buttonStyle(.glubeePrimary).disabled(true)
    }
    .padding(Spacing.gutter)
}
