//
//  Theme.swift
//  glucose
//
//  디자인 v4 기본값 (docs/ios-design-v4.md 1장). 색은 Assets.xcassets/Colors에 있고
//  Xcode가 만든 심볼(Color.brand 등)로 쓴다. 여기에는 간격·모양·글꼴만 둔다.
//

import SwiftUI

enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    /// 화면 좌우 여백
    static let gutter: CGFloat = 20
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
}

enum Radius {
    static let field: CGFloat = 12
    static let card: CGFloat = 16
    static let sheet: CGFloat = 24
}

enum Metrics {
    /// 주 버튼 높이
    static let buttonHeight: CGFloat = 52
    /// 터치 영역 최소 크기
    static let minTapTarget: CGFloat = 44
}

extension Font {
    /// 홈·온보딩의 큰 인사말, 연속일 같은 핵심 숫자
    static let display = Font.system(.largeTitle, design: .rounded, weight: .bold)
    /// 화면 제목, 글루비 말풍선
    static let headline1 = Font.system(.title2, design: .rounded, weight: .bold)
    /// 카드·섹션 제목
    static let headline2 = Font.system(.headline)
    static let body1 = Font.system(.body)
    static let body2 = Font.system(.subheadline)
    static let caption1 = Font.system(.footnote)
    /// "이번 달", "기록" 같은 작은 섹션 라벨
    static let sectionLabel = Font.system(.caption, weight: .semibold)
}
