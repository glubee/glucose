//
//  LoginView.swift
//  glucose
//
//  온보딩을 마친 뒤 로그아웃했을 때 보이는 로그인 화면(v5). 처음 실행은 온보딩 마지막 단계에서 로그인한다.
//

import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @State private var viewModel = AuthViewModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: Spacing.l) {
            Spacer()

            VStack(spacing: Spacing.m) {
                MascotView(pose: .wave, size: 160, motion: .flyIn, floats: true)
                VStack(spacing: Spacing.xs) {
                    Text("다시 만나요!")
                        .font(.headline1)
                        .foregroundStyle(Color.textPrimary)
                    Text("로그인하면 모아둔 기록을 이어서 볼 수 있어요.")
                        .font(.body2)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()

            VStack(spacing: Spacing.s) {
                SignInWithAppleButton(.signIn) { request in
                    request.nonce = viewModel.currentNonce
                } onCompletion: { result in
                    viewModel.handle(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: Metrics.buttonHeight)
                .clipShape(Capsule())
                .disabled(viewModel.isLoading)
                .overlay { if viewModel.isLoading { ProgressView() } }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption1)
                        .foregroundStyle(Color.alert)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.bottom, Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
    }
}

#Preview {
    LoginView()
}
