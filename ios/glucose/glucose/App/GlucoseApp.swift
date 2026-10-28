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
        } else if ProcessInfo.processInfo.arguments.contains("-tabs") {
            // 로그인 없이 탭 화면 보기
            RootTabView()
        } else if ProcessInfo.processInfo.arguments.contains("-settings") {
            SettingsView()
        } else if ProcessInfo.processInfo.arguments.contains("-chartDetail") {
            // 로그인 없이 그래프 크게 보기(예시 데이터)
            let sample = ReportSamples.daily(.now)
            GlucoseDayDetailView(day: .now, points: sample.1, episodes: sample.0.episodes,
                                 insulinEvents: sample.0.insulinEvents ?? [])
        } else if ProcessInfo.processInfo.arguments.contains("-reports") {
            // 로그인 없이 리포트 탭 보기. -reportSample: 예시 값, -clinician: 진료용 리포트 시트, -weekly: 주간만
            if ProcessInfo.processInfo.arguments.contains("-clinician") {
                ClinicianReportView()
            } else {
                ReportsView()
            }
        } else if ProcessInfo.processInfo.arguments.contains("-graphUpload") {
            // 로그인 없이 혈당 가져오기 화면 보기(-graphUploadSample: 예시 4장)
            GraphUploadView()
        } else if ProcessInfo.processInfo.arguments.contains("-login") {
            LoginView()
        } else if ProcessInfo.processInfo.arguments.contains("-records") {
            // 로그인 없이 전체 기록 화면 보기(로그인 전이라 오류 상태로 보인다)
            RecordsView()
        } else if ProcessInfo.processInfo.arguments.contains("-insulinForm") {
            InsulinRecordFormView(mode: .edit(id: UUID()), units: 6, kind: "식사", onSaved: {})
        } else if ProcessInfo.processInfo.arguments.contains("-review") {
            ReviewView()
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
        } else if ProcessInfo.processInfo.arguments.contains("-capture") {
            // 로그인 없이 음식 사진 기록 화면 보기
            PhotoCaptureView()
        } else if ProcessInfo.processInfo.arguments.contains("-recognition") {
            // 로그인 없이 음식 확인 화면 보기(예시 음식 2개)
            NavigationStack { RecognitionResultView(photoId: UUID(), context: .meal) {} }
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
