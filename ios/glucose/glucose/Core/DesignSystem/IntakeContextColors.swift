//
//  IntakeContextColors.swift
//  glucose
//
//  음식 기록 상황별 색. 식사·간식·저혈당 대응·술이 그래프·기록 줄·홈 시간줄에서 한눈에 구분되게 한 곳에서 정한다.
//  인슐린은 Color.insulin(보라)을 그대로 쓴다. 색만으로 구분하지 않도록 아이콘(IntakeContext.systemImage)도 같이 쓴다.
//

import SwiftUI
import UIKit

extension IntakeContext {
    /// 선·아이콘 색
    var tint: Color {
        switch self {
        case .meal: Self.dynamic(light: (0.85, 0.50, 0.08), dark: (0.98, 0.68, 0.30))      // 주황
        case .snack: Self.dynamic(light: (0.16, 0.50, 0.82), dark: (0.45, 0.70, 0.98))     // 파랑
        case .hypoTreatment: .mintStrong                                                     // 민트
        case .alcohol: Self.dynamic(light: (0.80, 0.25, 0.42), dark: (0.98, 0.50, 0.62))   // 장미
        }
    }

    /// 아이콘 뒤 바탕색
    var softFill: Color {
        switch self {
        case .meal: Self.dynamic(light: (1.0, 0.92, 0.80), dark: (0.36, 0.25, 0.10))
        case .snack: Self.dynamic(light: (0.87, 0.93, 1.0), dark: (0.13, 0.24, 0.38))
        case .hypoTreatment: .mintSoft
        case .alcohol: Self.dynamic(light: (0.99, 0.89, 0.92), dark: (0.38, 0.14, 0.21))
        }
    }

    private static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}
