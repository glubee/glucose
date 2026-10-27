//
//  OnboardingView.swift
//  glucose
//
//  첫 설정(디자이너 v5 프로토타입): 위 8칸 진행 막대 → 왼쪽 위 큰 문장(한 글자씩, 노란 커서) →
//  해·풀밭·꽃 장면 위의 큰 글루비 → 말을 마치면 아래에서 둥근 입력칸이 올라온다.
//

import AuthenticationServices
import SwiftUI

struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel()
    @State private var authViewModel = AuthViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            progress
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.xs)

            TypingText(text: viewModel.line, showsCaret: true, caretHeight: 26) {
                viewModel.lineFinished()
            }
            .font(.pretendard(30, relativeTo: .largeTitle, weight: .bold))
            .tracking(-1.1)
            .lineSpacing(4)
            .foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.l)
            .accessibilityAddTraits(.isHeader)

            MeadowScene {
                GeometryReader { geometry in
                    MascotView(pose: viewModel.pose, size: min(236, geometry.size.height - 8),
                               motion: viewModel.motion, floats: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(maxHeight: .infinity)

            if viewModel.isPanelUp {
                panel
                    .transition(.move(edge: .bottom))
            }
        }
        .background(Color.canvas)
        .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.12), value: viewModel.isPanelUp)
        .onChange(of: AuthSession.shared.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated && viewModel.step == .signIn { viewModel.finish() }
        }
    }

    // MARK: - 진행 막대

    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(0..<viewModel.stepCount, id: \.self) { index in
                Capsule()
                    .fill(index <= viewModel.progressIndex ? Color.textPrimary : Color.line)
                    .frame(height: 4)
            }
        }
        .animation(.easeOut(duration: 0.45), value: viewModel.progressIndex)
        .accessibilityElement()
        .accessibilityLabel("\(viewModel.stepCount)단계 중 \(viewModel.progressIndex + 1)단계")
    }

    // MARK: - 아래 입력칸

    private var panel: some View {
        VStack(spacing: Spacing.s) {
            OnboardingStepContent(viewModel: viewModel)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 6) {
                if viewModel.step == .signIn {
                    signInButton
                } else {
                    Button(viewModel.primaryTitle) { Task { await viewModel.primary() } }
                        .buttonStyle(.glubeePrimary)
                        .disabled(viewModel.isReacting)
                }
                if viewModel.showsLater {
                    Button("나중에 할게요") { Task { await viewModel.later() } }
                        .font(.pretendard(15, relativeTo: .subheadline, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                        .frame(minHeight: Metrics.minTapTarget)
                        .disabled(viewModel.isReacting)
                } else {
                    Text("기록은 내 계정에만 보관돼요.")
                        .font(.caption1)
                        .foregroundStyle(Color.textSecondary)
                        .frame(minHeight: Metrics.minTapTarget)
                }
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.gutter)
        .padding(.bottom, Spacing.xs)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                .fill(Color.canvas)
                .shadow(color: Color.black.opacity(0.06), radius: 15, y: -12)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    @ViewBuilder
    private var signInButton: some View {
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
            if let message = authViewModel.errorMessage {
                Text(message).font(.caption1).foregroundStyle(Color.alert)
            }
        }
    }
}

#Preview {
    OnboardingView()
}
