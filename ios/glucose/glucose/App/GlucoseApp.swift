//
//  GlucoseApp.swift
//  glucose
//
//  Created by DavePark on 10/6/26.
//

import SwiftUI

@main
struct GlucoseApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            content
                .onOpenURL { DeepLinkRouter.shared.handle($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            // 업로드하지 못한 빠른 촬영 사진은 앱이 다시 열릴 때 재시도한다
            if phase == .active {
                Task { await PendingPhotoStore.shared.uploadPending() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        #if DEBUG
        // 실행 인자 -designCatalog 로 켜면 디자인 카탈로그를 바로 띄운다(시뮬레이터 확인용)
        if ProcessInfo.processInfo.arguments.contains("-designCatalog") {
            DesignCatalogView()
        } else {
            RootView()
        }
        #else
        RootView()
        #endif
    }
}
