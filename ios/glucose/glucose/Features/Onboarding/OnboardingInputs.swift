//
//  OnboardingInputs.swift
//  glucose
//
//  화면 아래 입력칸. 글루비가 말을 마치면 단계에 맞는 입력이 올라온다.
//

import AuthenticationServices
import SwiftUI

struct OnboardingInputPanel: View {
    @Bindable var viewModel: OnboardingViewModel
    let authViewModel: AuthViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: Spacing.s) {
            switch viewModel.step {
            case .hello:
                Button("좋아요!") { viewModel.startChatting() }.buttonStyle(.glubeePrimary)
            case .name:
                NameInput(viewModel: viewModel)
            case .howTo:
                Button("알겠어요") { viewModel.acknowledgeHowTo() }.buttonStyle(.glubeePrimary)
            case .insulin:
                InsulinInput(viewModel: viewModel)
            case .dayClose:
                DatePicker("하루 마무리 시각", selection: $viewModel.dayClose, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(height: 120)
                    .clipped()
                Button("\(viewModel.timeText(viewModel.dayClose))에 할게요") { viewModel.submitDayClose() }
                    .buttonStyle(.glubeePrimary)
            case .notifications:
                Button("알림 받을게요") { Task { await viewModel.requestNotifications() } }
                    .buttonStyle(.glubeePrimary)
                Button("괜찮아요") { viewModel.declineNotifications() }
                    .buttonStyle(.glubeeSecondary)
            case .widget:
                Button("알겠어요") { viewModel.acknowledgeWidget() }.buttonStyle(.glubeePrimary)
            case .signIn:
                signIn
            }

            if viewModel.canSkip {
                Button("나중에 할게요") { viewModel.skip() }
                    .font(.body2)
                    .foregroundStyle(Color.textSecondary)
                    .frame(minHeight: Metrics.minTapTarget)
            }
        }
    }

    @ViewBuilder
    private var signIn: some View {
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

/// 채팅 입력처럼: 입력칸 + 보내기 버튼
private struct NameInput: View {
    @Bindable var viewModel: OnboardingViewModel
    @FocusState private var focused: Bool

    private var isEmpty: Bool { viewModel.nickname.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            TextField("부를 이름", text: $viewModel.nickname)
                .font(.body1)
                .textContentType(.nickname)
                .submitLabel(.send)
                .focused($focused)
                .onSubmit { viewModel.submitName() }
                .padding(.horizontal, Spacing.m)
                .frame(minHeight: Metrics.buttonHeight)
                .background(Color.surfaceMuted, in: Capsule())
            SendButton(disabled: isEmpty) { viewModel.submitName() }
        }
        .onAppear { focused = true }
    }
}

private struct InsulinInput: View {
    @Bindable var viewModel: OnboardingViewModel
    @State private var name = ""
    @State private var unitsText = ""

    private var isEmpty: Bool { name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                VStack(spacing: 0) {
                    TextField("제품 이름 (예: 초속효성 인슐린)", text: $name)
                        .frame(minHeight: Metrics.minTapTarget)
                    Divider()
                    TextField("평소 단위 (선택)", text: $unitsText)
                        .keyboardType(.decimalPad)
                        .frame(minHeight: Metrics.minTapTarget)
                }
                .font(.body1)
                .padding(.horizontal, Spacing.m)
                .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.card))

                SendButton(disabled: isEmpty) {
                    viewModel.addInsulin(name: name, units: Double(unitsText.replacingOccurrences(of: ",", with: ".")))
                    name = ""
                    unitsText = ""
                }
            }
            if !viewModel.insulins.isEmpty {
                Button("다 했어요") { viewModel.finishInsulins() }.buttonStyle(.glubeePrimary)
            }
        }
    }
}

private struct SendButton: View {
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.body.weight(.bold))
                .foregroundStyle(Color.onBrand)
                .frame(width: Metrics.buttonHeight, height: Metrics.buttonHeight)
                .background(Color.brand, in: Circle())
        }
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityLabel("보내기")
    }
}
