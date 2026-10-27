//
//  RootTabView.swift
//  glucose
//

import SwiftUI

struct RootTabView: View {
    @State private var router = DeepLinkRouter.shared

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("홈", systemImage: "house") }

            RecordsView()
                .tabItem { Label("기록", systemImage: "list.bullet") }

            ReportsView()
                .tabItem { Label("리포트", systemImage: "chart.line.uptrend.xyaxis") }

            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape") }
        }
        // 위젯·단축어 주소로 열린 화면 (로그인 전에 들어온 요청도 여기서 이어서 연다)
        .fullScreenCover(isPresented: $router.showsQuickCapture) {
            QuickCaptureView()
        }
        .sheet(isPresented: $router.showsInsulinRecord) {
            InsulinConfirmView()
        }
        .task {
            // 로그인 직후에도 대기 중인 사진을 올린다
            await PendingPhotoStore.shared.uploadPending()
        }
    }
}

#Preview {
    RootTabView()
}
