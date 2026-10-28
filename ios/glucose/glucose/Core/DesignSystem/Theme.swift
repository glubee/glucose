//
//  Theme.swift
//  glucose
//
//  디자인 v5 기본값. 색은 Assets.xcassets/Colors(디자이너 "색 대응표")에 있고
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
    static let buttonHeight: CGFloat = 56
    /// 터치 영역 최소 크기
    static let minTapTarget: CGFloat = 44
}

/// Pretendard(SIL OFL). 등록 이름은 "Pretendard Variable"이고, 글꼴이 없으면 시스템 글꼴로 대체된다.
/// relativeTo로 글자 크기 설정(Dynamic Type)을 따른다.
extension Font {
    private static let family = "Pretendard Variable"

    static func pretendard(_ size: CGFloat, relativeTo style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .custom(family, size: size, relativeTo: style).weight(weight)
    }

    /// 연속일 같은 핵심 숫자
    static let bigNumber = pretendard(60, relativeTo: .largeTitle, weight: .black)
    /// 홈·온보딩의 큰 문장
    static let display = pretendard(30, relativeTo: .largeTitle, weight: .bold)
    /// 화면 제목
    static let headline1 = pretendard(24, relativeTo: .title, weight: .bold)
    /// 카드·섹션 제목
    static let headline2 = pretendard(17, relativeTo: .headline, weight: .semibold)
    static let body1 = pretendard(16, relativeTo: .body)
    static let body2 = pretendard(15, relativeTo: .subheadline)
    static let caption1 = pretendard(13, relativeTo: .footnote)
    /// "이번 달", "기록" 같은 작은 섹션 라벨
    static let sectionLabel = pretendard(12, relativeTo: .caption, weight: .semibold)
}
