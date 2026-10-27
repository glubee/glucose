//
//  GlucoseApp.swift
//  glucose
//
//  Created by DavePark on 10/6/26.
//

import SwiftUI

@main
struct GlucoseApp: App {
    var body: some Scene {
        WindowGroup {
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
}
