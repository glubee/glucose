//
//  OnboardingView.swift
//  glucose
//
//  글루비와 대화하는 첫 설정. 위는 진행 막대와 글루비(탭하면 꿈틀),
//  가운데는 대화, 아래는 글루비가 말을 마친 뒤 올라오는 입력칸.
//

import SwiftUI

struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel()
    @State private var authViewModel = AuthViewModel()
    @State private var wiggle = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVStack(spacing: Spacing.s) {
                    ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                        ChatBubbleRow(message: message, showsAvatar: showsAvatar(at: index))
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity))
                    }
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.m)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            // 말하는 중에 탭하면 바로 끝까지 보여준다
            .onTapGesture { viewModel.skipTyping() }

            if !viewModel.isBeeTalking {
                OnboardingInputPanel(viewModel: viewModel, authViewModel: authViewModel)
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.top, Spacing.s)
                    .padding(.bottom, Spacing.xs)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color.canvas)
        .animation(.spring(duration: 0.35), value: viewModel.messages.count)
        .animation(.spring(duration: 0.35), value: viewModel.isBeeTalking)
        .onAppear {
            viewModel.reduceMotion = reduceMotion
            viewModel.start()
        }
        .onChange(of: AuthSession.shared.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated && viewModel.step == .signIn { viewModel.finish() }
        }
    }

    private func showsAvatar(at index: Int) -> Bool {
        let next = index + 1
        guard next < viewModel.messages.count else { return true }
        return viewModel.messages[next].speaker == .user
    }

    private var header: some View {
        VStack(spacing: Spacing.s) {
            ProgressView(value: viewModel.progress)
                .tint(Color.brand)
                .accessibilityLabel("첫 설정 진행")
                .padding(.horizontal, Spacing.gutter)

            MascotView(pose: viewModel.pose, size: 88)
                .id(viewModel.pose)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
                .rotationEffect(.degrees(wiggle.isMultiple(of: 2) ? 0 : 8))
                .animation(.spring(duration: 0.25, bounce: 0.6), value: wiggle)
                .onTapGesture { wiggle += 1 }
                .sensoryFeedback(.impact(weight: .light), trigger: wiggle)
        }
        .padding(.top, Spacing.s)
        .animation(.spring(duration: 0.35), value: viewModel.pose)
    }
}

#Preview {
    OnboardingView()
}
