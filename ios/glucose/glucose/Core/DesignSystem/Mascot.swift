//
//  Mascot.swift
//  glucose
//
//  글루비 동작. 이미지는 Assets.xcassets/Mascot에 `bee_<동작>` 이름으로 넣는다
//  (디자인 요청서 1·2장). 아직 받지 못한 동작은 자리표시로 그린다.
//

import SwiftUI
import UIKit

enum MascotPose: String, CaseIterable {
    // v4에 있는 동작
    case wave, nod, think, thumbsup, cheer, camera, magnifier, rest, honeypot
    // 감정
    case nag, anxious, angry, sulky, sleep, celebrate
    // 온보딩·기타
    case flyin, curious, clock, point, breakTime = "break"

    var assetName: String { "bee_\(rawValue)" }
}

struct MascotView: View {
    let pose: MascotPose
    var size: CGFloat = 120

    var body: some View {
        Group {
            if let image = UIImage(named: pose.assetName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        // 장식 이미지라 VoiceOver는 옆의 말풍선 문장을 읽는다
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Circle().fill(Color.brandSoft)
            VStack(spacing: Spacing.xxs) {
                Text("🐝").font(.system(size: size * 0.35))
                Text(pose.rawValue)
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }
}

#Preview {
    MascotView(pose: .wave)
}
