//
//  RootTabView.swift
//  glucose
//

import SwiftUI

struct RootTabView: View {
    @State private var router = DeepLinkRouter.shared

    var body: some View {
        // 홈 · 리포트 · 기록 · 설정. 리포트의 전체 기록 시트도 같은 목록을 쓴다.
        TabView {
            HomeView()
                .tabItem { Label("홈", systemImage: "house.fill") }

            ReportsView()
                .tabItem { Label("리포트", systemImage: "chart.bar.fill") }

            RecordsView(showsCloseButton: false)
                .tabItem { Label("기록", systemImage: "list.bullet.rectangle") }

            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape.fill") }
        }
        #if DEBUG
        .id(LocalDemoSession.shared.generation)
        .safeAreaInset(edge: .top) {
            if LocalDemoSession.shared.isActive {
                Text("기기 데모 · 예시 데이터 · 서버에 저장되지 않아요")
                    .font(.caption1).foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity).padding(.vertical, Spacing.xs)
                    .background(Color.brandSoft)
                    .accessibilityIdentifier("localDemoNotice")
            }
        }
        #endif
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
            guard !RecordDataSource.isPreview else { return }
            // 로그인 직후에도 대기 중인 사진을 올린다
            await PendingPhotoStore.shared.uploadPending()
            #if DEBUG
            if DemoScenarioSeed.isEnabled { await DemoScenarioSeed.run() }
            if DemoDayCloseSync.isEnabled { await DemoDayCloseSync.run() }
            #endif
        }
    }
}

#Preview {
    RootTabView()
}
