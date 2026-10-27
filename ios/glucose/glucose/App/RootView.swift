//
//  RootView.swift
//  glucose
//
//  첫 실행: 글루비 온보딩(마지막 단계가 로그인) → 탭.
//  온보딩을 마친 뒤 로그아웃하면 온보딩 없이 로그인 화면만 보인다.
//

import SwiftUI

struct RootView: View {
    var body: some View {
        if !UserPreferences.shared.onboardingCompleted {
            OnboardingView()
        } else if AuthSession.shared.isAuthenticated {
            RootTabView()
        } else {
            LoginView()
        }
    }
}

#Preview {
    RootView()
}
