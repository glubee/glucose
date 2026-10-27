//
//  LocalDataEraser.swift
//  glucose
//
//  계정을 지우면 기기에 남은 개인 데이터도 지운다: 설정 값(이름·평소 인슐린·마무리 시각·온보딩 완료),
//  확인 대기 사진, 하루 마무리·연속 완성일 기록, 위젯에 보이는 값, 예약·표시된 알림. 다음 실행은 온보딩부터 시작한다.
//  로그아웃은 지우지 않는다(같은 사람이 다시 로그인할 수 있으므로).
//

import Foundation
import UserNotifications

@MainActor
enum LocalDataEraser {
    static func eraseAll() async {
        PendingPhotoStore.shared.removeAll()
        DayCloseStore.shared.reset()
        WidgetSnapshot.erase()
        UserPreferences.shared.reset()
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}
