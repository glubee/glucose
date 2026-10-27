//
//  OnboardingView.swift
//  glucose
//
//  글루비 첫 설정. 왼쪽 위에 글루비가 지금 하는 말 한 문장(한 글자씩), 가운데 큰 글루비(탭하면 꿈틀),
//  아래는 글루비가 말을 마친 뒤 올라오는 입력칸. 디자이너 시안이 나오면 맞춰 다듬는다.
//

import SwiftUI

struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel()
    @State private var authViewModel = AuthViewModel()
    @State private var wiggle = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressView(value: viewModel.progress)
                .tint(Color.brand)
                .accessibilityLabel("첫 설정 진행")
                .padding(.top, Spacing.s)

            line
                .padding(.top, Spacing.xl)

            Spacer(minLength: Spacing.m)

            MascotView(pose: viewModel.pose, size: 220)
                .id(viewModel.pose)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .rotationEffect(.degrees(wiggle.isMultiple(of: 2) ? 0 : 6))
                .animation(.spring(duration: 0.25, bounce: 0.6), value: wiggle)
                .onTapGesture { wiggle += 1 }
                .sensoryFeedback(.impact(weight: .light), trigger: wiggle)
                .frame(maxWidth: .infinity)

            Spacer(minLength: Spacing.m)

            if !viewModel.isBeeTalking {
                OnboardingInputPanel(viewModel: viewModel, authViewModel: authViewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.bottom, Spacing.xs)
        .background(Color.canvas)
        // 말하는 중에 화면을 탭하면 바로 끝까지 보여준다
        .contentShape(Rectangle())
        .onTapGesture { viewModel.skipTyping() }
        .animation(.spring(duration: 0.35), value: viewModel.pose)
        .animation(.spring(duration: 0.35), value: viewModel.isBeeTalking)
        .onAppear {
            viewModel.reduceMotion = reduceMotion
            viewModel.start()
        }
        .onChange(of: AuthSession.shared.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated && viewModel.step == .signIn { viewModel.finish() }
        }
    }

    /// 글루비가 지금 하는 말. 다음 문장이 오면 이 자리를 대신한다
    @ViewBuilder
    private var line: some View {
        if let message = viewModel.currentLine {
            VStack(alignment: .leading, spacing: Spacing.m) {
                TypewriterText(text: message.text, startedAt: message.startedAt)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if message.attachment == .howTo {
                    HowToCard()
                }
            }
            .id(message.id)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("글루비: \(message.text)")
        }
    }
}

#Preview {
    OnboardingView()
}
