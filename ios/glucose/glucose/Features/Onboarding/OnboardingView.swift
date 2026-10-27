//
//  OnboardingView.swift
//  glucose
//
//  한 화면에 질문 하나. 위는 글루비(탭하면 꿈틀), 가운데 입력, 아래 버튼 하나.
//

import AuthenticationServices
import SwiftUI

struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel()
    @State private var authViewModel = AuthViewModel()
    @State private var wiggle = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(spacing: Spacing.l) {
                    bee
                    stepContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.bottom, Spacing.l)
            }
            .scrollDismissesKeyboard(.interactively)

            bottomAction
                .padding(.horizontal, Spacing.gutter)
                .padding(.bottom, Spacing.s)
        }
        .background(Color.canvas)
        .animation(.spring(duration: 0.35), value: viewModel.step)
        .onChange(of: AuthSession.shared.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated && viewModel.step == .signIn { viewModel.finish() }
        }
    }

    // MARK: - 위쪽: 뒤로, 진행 막대, 건너뛰기

    private var topBar: some View {
        HStack(spacing: Spacing.s) {
            Button {
                viewModel.back()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: Metrics.minTapTarget, height: Metrics.minTapTarget)
            }
            .opacity(viewModel.canGoBack ? 1 : 0)
            .disabled(!viewModel.canGoBack)
            .accessibilityLabel("이전")

            ProgressView(value: viewModel.progress)
                .tint(Color.brand)
                .accessibilityLabel("첫 설정 진행")

            Button("나중에") { viewModel.next() }
                .font(.body2)
                .frame(minWidth: Metrics.minTapTarget, minHeight: Metrics.minTapTarget)
                .opacity(viewModel.canSkip ? 1 : 0)
                .disabled(!viewModel.canSkip)
        }
        .foregroundStyle(Color.textSecondary)
        .padding(.horizontal, Spacing.xs)
    }

    // MARK: - 글루비

    private var bee: some View {
        VStack(spacing: Spacing.m) {
            MascotView(pose: viewModel.beePose, size: 160)
                .id(viewModel.beePose)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
                .rotationEffect(.degrees(wiggle.isMultiple(of: 2) ? 0 : 8))
                .animation(.spring(duration: 0.25, bounce: 0.6), value: wiggle)
                .onTapGesture { wiggle += 1 }
                .sensoryFeedback(.impact(weight: .light), trigger: wiggle)

            Text(viewModel.beeLine)
                .font(.headline1)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .id(viewModel.beeLine)
                .transition(.opacity)
                .accessibilityLabel("글루비: \(viewModel.beeLine)")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.m)
        .animation(.spring(duration: 0.35), value: viewModel.beeLine)
    }

    // MARK: - 단계별 입력

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .hello:
            EmptyView()
        case .name:
            OnboardingNameStep(viewModel: viewModel)
        case .howTo:
            OnboardingHowToStep()
        case .insulin:
            OnboardingInsulinStep(viewModel: viewModel)
        case .dayClose:
            DatePicker("하루 마무리 시각", selection: $viewModel.dayClose, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
        case .tone:
            OnboardingToneStep(viewModel: viewModel)
        case .notifications:
            Text("하루 최대 2번, 밤 11시부터 아침 8시까지는 보내지 않아요. 알림에는 혈당이나 음식 내용을 쓰지 않아요.")
                .font(.body2)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        case .widget:
            OnboardingWidgetStep()
        case .signIn:
            if let message = authViewModel.errorMessage {
                Text(message).font(.caption1).foregroundStyle(Color.alert)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - 아래 버튼

    @ViewBuilder
    private var bottomAction: some View {
        switch viewModel.step {
        case .hello:
            Button("좋아, 시작하자") { viewModel.next() }.buttonStyle(.glubeePrimary)
        case .name:
            Button("다음") {
                viewModel.commitName()
                viewModel.next()
            }
            .buttonStyle(.glubeePrimary)
            .disabled(viewModel.nickname.trimmingCharacters(in: .whitespaces).isEmpty)
        case .howTo:
            Button("알겠어") { viewModel.next() }.buttonStyle(.glubeePrimary)
        case .insulin:
            Button("다음") { viewModel.next() }
                .buttonStyle(.glubeePrimary)
                .disabled(viewModel.insulins.isEmpty)
        case .dayClose:
            Button("이 시간으로") { viewModel.next() }.buttonStyle(.glubeePrimary)
        case .tone:
            Button("이 말투로") { viewModel.next() }.buttonStyle(.glubeePrimary)
        case .notifications:
            if viewModel.notificationChoice == .undecided {
                Button("알림 받기") { Task { await viewModel.requestNotifications() } }
                    .buttonStyle(.glubeePrimary)
            } else {
                Button("다음") { viewModel.next() }.buttonStyle(.glubeePrimary)
            }
        case .widget:
            Button("다음") { viewModel.next() }.buttonStyle(.glubeePrimary)
        case .signIn:
            if AuthSession.shared.isAuthenticated {
                // 이미 로그인한 채로 업데이트한 사용자
                Button("시작하기") { viewModel.finish() }.buttonStyle(.glubeePrimary)
            } else {
                SignInWithAppleButton(.signIn) { request in
                    request.nonce = authViewModel.currentNonce
                } onCompletion: { result in
                    authViewModel.handle(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: Metrics.buttonHeight)
                .clipShape(Capsule())
                .disabled(authViewModel.isLoading)
                .overlay { if authViewModel.isLoading { ProgressView() } }
            }
        }
    }
}

#Preview {
    OnboardingView()
}
