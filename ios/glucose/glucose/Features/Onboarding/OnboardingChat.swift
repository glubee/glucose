//
//  OnboardingChat.swift
//  glucose
//
//  대화 말풍선. 글루비는 왼쪽(아바타 + 민트 말풍선, 한 글자씩), 사용자는 오른쪽(노랑).
//

import SwiftUI

/// startedAt부터 한 글자씩 보여주는 글. 다 찍히면 타이머를 멈춘다
struct TypewriterText: View {
    let text: String
    let startedAt: Date

    private var characters: [Character] { Array(text) }

    var body: some View {
        let total = characters.count
        let finished = Date.now.timeIntervalSince(startedAt) >= OnboardingViewModel.typingDuration(of: text)
        TimelineView(.animation(minimumInterval: 0.03, paused: finished)) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            let count = min(total, max(0, Int(elapsed / OnboardingViewModel.characterInterval) + 1))
            // 다 찍힌 글을 투명하게 깔아 말풍선 크기가 처음부터 고정되게 한다
            ZStack(alignment: .topLeading) {
                Text(text).hidden()
                Text(String(characters.prefix(count)))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}

struct ChatBubbleRow: View {
    let message: ChatMessage
    /// 글루비가 연달아 말하면 마지막 말풍선에만 아바타를 붙인다
    var showsAvatar = true

    var body: some View {
        switch message.speaker {
        case .bee(let pose):
            HStack(alignment: .bottom, spacing: Spacing.xs) {
                MascotView(pose: pose, size: 36)
                    .opacity(showsAvatar ? 1 : 0)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    TypewriterText(text: message.text, startedAt: message.startedAt)
                        .font(.body1)
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, Spacing.m)
                        .padding(.vertical, Spacing.s)
                        .background(Color.mintSoft, in: BubbleShape(isMine: false))
                    if message.attachment == .howTo {
                        HowToCard()
                    }
                }
                Spacer(minLength: Spacing.xl)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("글루비: \(message.text)")
        case .user:
            HStack {
                Spacer(minLength: Spacing.xl)
                Text(message.text)
                    .font(.body1)
                    .foregroundStyle(Color.onBrand)
                    .padding(.horizontal, Spacing.m)
                    .padding(.vertical, Spacing.s)
                    .background(Color.brand, in: BubbleShape(isMine: true))
            }
            .accessibilityLabel("나: \(message.text)")
        }
    }
}

/// 말하는 쪽 아래 모서리만 덜 둥근 말풍선
struct BubbleShape: Shape {
    let isMine: Bool

    func path(in rect: CGRect) -> Path {
        let large: CGFloat = 18
        let small: CGFloat = 4
        return UnevenRoundedRectangle(
            topLeadingRadius: large,
            bottomLeadingRadius: isMine ? large : small,
            bottomTrailingRadius: isMine ? small : large,
            topTrailingRadius: large
        ).path(in: rect)
    }
}

struct HowToCard: View {
    private let items: [(icon: String, title: String, detail: String)] = [
        ("camera.fill", "먹을 때 찰칵", "사진 한 장이면 돼요. 확인은 나중에 해요."),
        ("syringe.fill", "맞을 때 한 번", "평소 인슐린이 채워져 있어서 확인만 누르면 돼요."),
        ("moon.stars.fill", "밤에 같이 정리", "리브레 그래프를 올리고 빠진 기록을 채우면 하루가 완성돼요."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ForEach(items, id: \.title) { item in
                HStack(alignment: .top, spacing: Spacing.s) {
                    Image(systemName: item.icon)
                        .font(.body)
                        .foregroundStyle(Color.onBrand)
                        .frame(width: 36, height: 36)
                        .background(Color.brand, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.headline2).foregroundStyle(Color.textPrimary)
                        Text(item.detail).font(.body2).foregroundStyle(Color.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }
}
