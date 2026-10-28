//
//  RootTabView.swift
//  glucose
//

import SwiftUI

struct RootTabView: View {
    @State private var router = DeepLinkRouter.shared

    var body: some View {
        // v5 탭: 홈 · 리포트 · 리뷰 · 설정 (지난 기록 목록은 리포트의 "전체 기록")
        TabView {
            HomeView()
                .tabItem { Label("홈", systemImage: "house.fill") }

            ReportsView()
                .tabItem { Label("리포트", systemImage: "chart.bar.fill") }

            ReviewView()
                .tabItem { Label("리뷰", systemImage: "doc.text.fill") }

            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape.fill") }
        }
        // 위젯·단축어 주소로 열린 화면 (로그인 전에 들어온 요청도 여기서 이어서 연다)
        .fullScreenCover(isPresented: $router.showsQuickCapture) {
            QuickCaptureView()
        }
        .sheet(isPresented: $router.showsInsulinRecord) {
            InsulinConfirmView()
        }
        .fullScreenCover(isPresented: $router.showsDayClose) {
            DayCloseView()
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
