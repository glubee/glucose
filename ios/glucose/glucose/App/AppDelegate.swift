//
//  AppDelegate.swift
//  glucose
//
//  알림을 누르면 알림에 담긴 주소(예: glubee://day-close)로 화면을 연다.
//

import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NudgeScheduler.registerCategories()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // 알림 버튼(사진 찍기 / 투여 확인)을 눌렀으면 그 화면, 아니면 알림에 담긴 주소
        if let url = NudgeScheduler.url(forAction: response.actionIdentifier) {
            await MainActor.run { _ = DeepLinkRouter.shared.handle(url) }
            return
        }
        guard let string = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: string) else { return }
        await MainActor.run { _ = DeepLinkRouter.shared.handle(url) }
    }

    /// 앱을 쓰는 중에도 알림을 보여준다
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
