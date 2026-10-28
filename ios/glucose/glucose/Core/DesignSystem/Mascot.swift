//
//  Mascot.swift
//  glucose
//
//  글루비 v5. 이미지는 Assets.xcassets/Mascot에 `bee_<동작>` PDF로 있다(다크 모드용 포함).
//  움직임은 디자이너 v5 코드(GlubeeMotion)를 옮긴 것이다. Lottie 없이 1초 안팎.
//

import SwiftUI
import UIKit

enum MascotPose: String, CaseIterable {
    // v4 동작을 v5 몸으로
    case wave, photo, note, happy, calendar
    case nod, think, thumbsup, cheer, camera, magnifier, rest, honeypot
    // 감정
    case nag, anxious, angry, sulky, sleep, celebrate
    // 온보딩·기타
    case flyin, curious, clock
    case pointLeft = "point_left", pointRight = "point_right", breakTime = "break"

    var assetName: String { "bee_\(rawValue)" }

    /// 오류·실패·미기록 화면에 쓰면 안 되는 웃는 동작
    var isSmiling: Bool {
        switch self {
        case .wave, .photo, .note, .happy, .calendar, .thumbsup, .cheer, .camera,
             .honeypot, .celebrate, .flyin, .clock, .pointLeft, .pointRight:
            true
        default:
            false
        }
    }
}

/// 등장·반응 움직임
enum MascotMotion {
    case none, pop, flyIn, shake, jump
}

/// 글루비 한 마리. pose가 바뀔 때마다 motion을 한 번 재생하고, 평소에는 천천히 위아래로 떠 있다.
/// "동작 줄이기"가 켜져 있으면 움직이지 않는다.
struct MascotView: View {
    let pose: MascotPose
    var size: CGFloat = 120
    var motion: MascotMotion = .pop
    var floats = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bob = false
    @State private var x: CGFloat = 0
    @State private var y: CGFloat = 0
    @State private var angle: Double = 0
    @State private var scaleX: CGFloat = 1
    @State private var scaleY: CGFloat = 1
    @State private var alpha: Double = 1

    var body: some View {
        Group {
            if UIImage(named: pose.assetName) != nil {
                Image(pose.assetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(x: scaleX, y: scaleY, anchor: .bottom)
        .rotationEffect(.degrees(angle))
        .offset(x: x, y: y + (floats && bob && !reduceMotion ? -6 : 0))
        .opacity(alpha)
        .task(id: pose) { await play(reduceMotion ? .none : motion) }
        .onAppear {
            guard floats, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { bob = true }
        }
        // 장식 이미지라 VoiceOver는 옆의 문장을 읽는다
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Circle().fill(Color.brandSoft)
            Text("🐝").font(.system(size: size * 0.35))
        }
    }

    private func set(_ dx: CGFloat = 0, _ dy: CGFloat = 0, rotation: Double = 0,
                     scaleX sx: CGFloat = 1, scaleY sy: CGFloat = 1, opacity: Double = 1) {
        x = dx; y = dy; angle = rotation; scaleX = sx; scaleY = sy; alpha = opacity
    }

    private func step(_ animation: Animation, _ seconds: Double, _ change: () -> Void) async {
        withAnimation(animation, change)
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func play(_ motion: MascotMotion) async {
        switch motion {
        case .none:
            set()
        case .pop:
            set(scaleX: 0.86, scaleY: 0.86)
            await step(.spring(duration: 0.22, bounce: 0.2), 0.22) { set(scaleX: 1.06, scaleY: 1.06) }
            await step(.bouncy(duration: 0.28), 0.28) { set() }
        case .flyIn:
            set(-180, -40, rotation: -18, scaleX: 0.7, scaleY: 0.7, opacity: 0)
            await step(.timingCurve(0.2, 0.9, 0.3, 1, duration: 0.65), 0.65) {
                set(10, 6, rotation: 4, scaleX: 1.02, scaleY: 1.02)
            }
            await step(.bouncy(duration: 0.45), 0.45) { set() }
        case .shake:
            for rotation in [-5.0, 4, -2, 0] {
                await step(.easeInOut(duration: 0.12), 0.12) { set(rotation: rotation) }
            }
        case .jump:
            await step(.easeOut(duration: 0.14), 0.14) { set(0, 4, scaleX: 1.06, scaleY: 0.92) }
            await step(.easeOut(duration: 0.24), 0.24) { set(0, -26, scaleX: 0.96, scaleY: 1.05) }
            await step(.bouncy(duration: 0.32), 0.32) { set() }
        }
    }
}

#Preview {
    MascotView(pose: .flyin, size: 200, motion: .flyIn, floats: true)
}
