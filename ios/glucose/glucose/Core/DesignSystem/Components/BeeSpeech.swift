//
//  BeeSpeech.swift
//  glucose
//
//  글루비 + 말풍선. 하루 마무리, 음식 확인("맞나요?"), 온보딩에서 쓴다.
//  규칙: 글루비는 기록 행동에만 반응한다. 혈당 수치에 대한 평가 문구를 넣지 않는다.
//

import SwiftUI

struct BeeSpeech: View {
    enum Tone {
        /// 민트 말풍선. 글루비가 묻거나 안내할 때
        case mint
        /// 연노랑 말풍선. 인식 결과를 확인할 때
        case brand

        var fill: Color { self == .mint ? .mintSoft : .brandSoft }
    }

    let pose: MascotPose
    let text: String
    var tone: Tone = .mint
    var mascotSize: CGFloat = 44

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.s) {
            MascotView(pose: pose, size: mascotSize)
            Text(text)
                .font(.headline2)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tone.fill, in: RoundedRectangle(cornerRadius: Radius.card))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("글루비: \(text)")
    }
}

#Preview {
    VStack(spacing: Spacing.m) {
        BeeSpeech(pose: .curious, text: "점심엔 뭘 드셨어요?")
        BeeSpeech(pose: .think, text: "사과랑 우유로 보이는데, 맞나요?", tone: .brand)
    }
    .padding(Spacing.gutter)
}
