//
//  TypingText.swift
//  glucose
//
//  한 글자씩 찍히는 글(디자이너 v5 프로토타입: 38ms 간격, 끝에 노란 커서 깜빡임).
//  "동작 줄이기"면 바로 다 보여준다. VoiceOver는 처음부터 전체 문장을 읽는다.
//

import SwiftUI

struct TypingText: View {
    let text: String
    var interval: Duration = .milliseconds(38)
    /// 문장 끝 노란 커서(온보딩 큰 문장)
    var showsCaret = false
    var caretHeight: CGFloat = 26
    var onFinished: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0
    @State private var caretOn = true

    var body: some View {
        // 다 찍힌 글을 투명하게 깔아 줄바꿈 때문에 레이아웃이 흔들리지 않게 한다
        ZStack(alignment: .topLeading) {
            Text(text).hidden()
            (Text(String(text.prefix(shown))) + caret)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .task(id: text) { await type() }
    }

    private var caret: Text {
        guard showsCaret else { return Text("") }
        return Text(" ") + Text(Image(systemName: "poweron"))
            .font(.system(size: caretHeight, weight: .heavy))
            .foregroundColor(caretOn ? .brand : .clear)
            .baselineOffset(-3)
    }

    private func type() async {
        if reduceMotion {
            shown = text.count
            onFinished()
            return
        }
        shown = 0
        for index in 1...max(text.count, 1) {
            try? await Task.sleep(for: interval)
            if Task.isCancelled { return }
            shown = index
        }
        onFinished()
        guard showsCaret else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            caretOn.toggle()
        }
    }
}
