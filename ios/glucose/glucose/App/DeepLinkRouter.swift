//
//  DeepLinkRouter.swift
//  glucose
//
//  위젯·단축어가 여는 주소: glubee://capture(빠른 촬영), glubee://insulin(인슐린 투여 확인).
//  로그인 전이나 온보딩 중에 열리면 요청을 기억해 두었다가 탭 화면이 뜨면 연다.
//

import Foundation

@Observable
final class DeepLinkRouter {

    static let shared = DeepLinkRouter()
    static let scheme = "glubee"

    var showsQuickCapture = false
    var showsInsulinRecord = false

    /// 처리한 주소면 true
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme == Self.scheme else { return false }
        switch url.host {
        case "capture":
            showsInsulinRecord = false
            showsQuickCapture = true
        case "insulin":
            showsQuickCapture = false
            showsInsulinRecord = true
        default:
            return false
        }
        return true
    }
}
