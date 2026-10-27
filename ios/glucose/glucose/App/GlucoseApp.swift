//
//  GlucoseApp.swift
//  glucose
//
//  Created by DavePark on 10/6/26.
//

import SwiftUI

@main
struct GlucoseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
                DayCloseStore.shared.applyHoneypots()
                WidgetSnapshot.refresh()
                Task { await NudgeScheduler.refresh() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        #if DEBUG
        // 실행 인자 -designCatalog 로 켜면 디자인 카탈로그를 바로 띄운다(시뮬레이터 확인용)
        if ProcessInfo.processInfo.arguments.contains("-designCatalog") {
            DesignCatalogView()
        } else if ProcessInfo.processInfo.arguments.contains("-home") {
            // 로그인 없이 홈만 보기. -homeSeed: 최근 6일 완성 + 꿀단지, -homeRest: 쉬어가는 중
            HomeView()
                .onAppear {
                    let store = DayCloseStore.shared
                    let arguments = ProcessInfo.processInfo.arguments
                    if arguments.contains("-homeSeed") || arguments.contains("-homeRest") {
                        store.reset()
                        for offset in (1...6).reversed() {
                            if let day = ReportDay.calendar.date(byAdding: .day, value: -offset, to: .now) {
                                store.markClosed(day)
                            }
                        }
                    }
                    if arguments.contains("-homeRest") { store.startRest(.noSensor, days: 3) }
                    if arguments.contains("-printNudges") { NudgeScheduler.debugPrintPlan() }
                }
        } else if ProcessInfo.processInfo.arguments.contains("-dayClose") {
            // 로그인 없이 하루 마무리 화면만 보기(확인 대기 사진 1장 예시, 업로드는 로그인 전이라 안 됨)
            DayCloseView()
                .onAppear {
                    guard PendingPhotoStore.shared.photos.isEmpty,
                          let data = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
                            .image(actions: { context in
                                UIColor.systemOrange.setFill()
                                context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
                            }).jpegData(compressionQuality: 0.8) else { return }
                    PendingPhotoStore.shared.add(imageData: data, context: .meal,
                                                 capturedAt: .now.addingTimeInterval(-3 * 3600))
                }
        } else if ProcessInfo.processInfo.arguments.contains("-insulinConfirm") {
            // 로그인 없이 투여 확인 화면만 보기(평소 인슐린 2개 예시)
            InsulinConfirmView(preferences: .debugSample)
        } else {
            RootView()
        }
        #else
        RootView()
        #endif
    }
}
