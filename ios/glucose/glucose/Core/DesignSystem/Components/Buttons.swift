//
//  Buttons.swift
//  glucose
//
//  v4 버튼 3종. 주 버튼은 노랑 배경 + 어두운 글자(흰 글자는 대비 부족).
//  사용: Button("기록 저장") { … }.buttonStyle(.glubeePrimary)
//

import SwiftUI

struct GlubeeButtonStyle: ButtonStyle {
    enum Kind {
        /// 노랑 캡슐. 화면당 하나
        case primary
        /// 테두리 캡슐. "아니에요", "취소"
        case secondary
        /// 회색 캡슐. 아직 끝낼 수 없는 단계의 마무리 버튼 등
        case muted
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
        case .primary: .onBrand
        case .secondary: .textPrimary
        case .muted: .textSecondary
        }
    }

    private var background: Color {
        switch kind {
        case .primary: .brand
        case .secondary: .canvas
        case .muted: .surfaceMuted
        }
    }
}

extension ButtonStyle where Self == GlubeeButtonStyle {
    static var glubeePrimary: GlubeeButtonStyle { GlubeeButtonStyle(kind: .primary) }
    static var glubeeSecondary: GlubeeButtonStyle { GlubeeButtonStyle(kind: .secondary) }
    static var glubeeMuted: GlubeeButtonStyle { GlubeeButtonStyle(kind: .muted) }
}

#Preview {
    VStack(spacing: Spacing.s) {
        Button("기록 저장") {}.buttonStyle(.glubeePrimary)
        Button("아니에요") {}.buttonStyle(.glubeeSecondary)
        Button("오늘 정리 마치기") {}.buttonStyle(.glubeeMuted)
        Button("기록 저장") {}.buttonStyle(.glubeePrimary).disabled(true)
    }
    .padding(Spacing.gutter)
}
