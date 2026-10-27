//
//  Honeycomb.swift
//  glucose
//
//  연속 완성일 부품(디자이너 v5 코드를 색 토큰에 맞춰 옮김): 벌집 칸, 이번 주 7칸, 큰 연속 숫자, 기념일 축하.
//

import SwiftUI

/// 이번 주 벌집 한 칸의 상태
enum HoneyCellState {
    case done
    /// 그래프가 짧아 기록만 저장하고 마친 날(완성으로 친다)
    case recordOnly
    case savedByHoneypot
    case rest
    case empty
    /// 오늘(아직 안 채움)
    case today
}

struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        // 42×46 기준 꼭짓점을 비율로
        let points: [(CGFloat, CGFloat)] = [(21, 2), (39, 12.5), (39, 33.5), (21, 44), (3, 33.5), (3, 12.5)]
        var path = Path()
        for (index, point) in points.enumerated() {
            let p = CGPoint(x: rect.minX + point.0 / 42 * rect.width, y: rect.minY + point.1 / 46 * rect.height)
            index == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        path.closeSubpath()
        return path
    }
}

private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 14 / 42, y: rect.height * 24 / 46))
        path.addLine(to: CGPoint(x: rect.width * 19 / 42, y: rect.height * 29 / 46))
        path.addLine(to: CGPoint(x: rect.width * 28 / 42, y: rect.height * 19 / 46))
        return path
    }
}

/// 한 칸. fillProgress를 0→1로 바꾸면 아래부터 꿀이 차오르고, 다 차면 체크가 그려진다
struct HoneyCell: View {
    var state: HoneyCellState
    var fillProgress: CGFloat = 1

    private var filled: Bool { state == .done || state == .recordOnly }

    var body: some View {
        ZStack {
            HexagonShape().fill(baseFill)
            if state == .today || filled {
                GeometryReader { geometry in
                    Rectangle().fill(Color.brand)
                        .frame(height: geometry.size.height * (filled ? 1 : fillProgress))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .clipShape(HexagonShape())
            }
            HexagonShape()
                .stroke(stroke, style: StrokeStyle(lineWidth: 2.2, lineJoin: .round, dash: state == .empty ? [4, 4] : []))
            switch state {
            case .done, .today:
                CheckShape()
                    .trim(from: 0, to: state == .done ? 1 : max(0, (fillProgress - 0.85) / 0.15))
                    // 노랑 위 체크는 다크 모드에서도 어둡게
                    .stroke(Color.onBrand, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            case .recordOnly:
                Image(systemName: "square.and.pencil")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.onBrand)
            case .savedByHoneypot:
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1).fill(Color(red: 0.66, green: 0.46, blue: 0.12)).frame(width: 11, height: 3)
                    RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.79, green: 0.54, blue: 0.23)).frame(width: 15, height: 13)
                }
            case .rest:
                Image(systemName: "pause")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.mintStrong)
            case .empty:
                EmptyView()
            }
        }
        .frame(width: 40, height: 44)
    }

    private var baseFill: Color {
        switch state {
        case .done, .recordOnly: .brand
        case .savedByHoneypot: .brandSofter
        case .rest: .mintSoft
        case .empty, .today: .canvas
        }
    }

    private var stroke: Color {
        switch state {
        case .done, .recordOnly: .brand
        case .savedByHoneypot: .brand.opacity(0.7)
        case .rest: .mintStrong.opacity(0.5)
        case .empty: .line
        case .today: .textPrimary
        }
    }
}

/// 월~일 7칸
struct WeekHoneycomb: View {
    let states: [HoneyCellState]
    /// 차오르는 연출을 할 칸(오늘)과 진행도
    var animatingIndex: Int? = nil
    var fillProgress: CGFloat = 1

    private let days = ["월", "화", "수", "목", "금", "토", "일"]

    var body: some View {
        HStack {
            ForEach(0..<7, id: \.self) { index in
                VStack(spacing: Spacing.xxs) {
                    // 연출 중이 아닌 "오늘" 칸은 비어 있다(테두리만)
                    HoneyCell(state: states[index],
                              fillProgress: index == animatingIndex ? fillProgress : (states[index] == .today ? 0 : 1))
                    Text(days[index]).font(.sectionLabel).foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("이번 주 \(states.filter { $0 == .done || $0 == .recordOnly }.count)일 완성")
    }
}

/// "연속 12일" 큰 숫자. 숫자가 바뀌면 굴러가듯 바뀐다
struct StreakNumber: View {
    var value: Int
    var font: Font = .bigNumber

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("연속").font(.headline1)
            Text("\(value)")
                .font(font)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
            Text("일").font(.headline1)
        }
        .foregroundStyle(Color.textPrimary)
        .accessibilityElement(children: .combine)
    }
}

/// 기념일(3·7·14·30·50·100일) 축하 전체 화면
struct MilestoneCelebrationView: View {
    static let milestones: Set<Int> = [3, 7, 14, 30, 50, 100]

    var days: Int
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.brandSoft.ignoresSafeArea()
            ConfettiBurst()
            VStack(spacing: Spacing.s) {
                Spacer()
                MascotView(pose: .celebrate, size: 230, motion: .jump)
                Text("\(days)").font(.pretendard(120, relativeTo: .largeTitle, weight: .black)).monospacedDigit()
                Text("일 연속으로 하루를 완성했어요").font(.headline1)
                Spacer()
                Button("계속하기", action: onClose).buttonStyle(.glubeePrimary)
            }
            .foregroundStyle(Color.textPrimary)
            .padding(Spacing.l)
        }
        .sensoryFeedback(.success, trigger: days)
    }
}

/// 꽃가루. 1.6초 한 번만, "동작 줄이기"면 안 뿌린다
private struct ConfettiBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fall = false
    private let pieces: [(x: CGFloat, dx: CGFloat, rotation: Double, color: Color, delay: Double)] = (0..<46).map { index in
        (CGFloat.random(in: 0...1), CGFloat.random(in: -60...60), Double.random(in: -360...360),
         [Color.brand, Color.mintStrong, Color.alert.opacity(0.7), Color.insulin.opacity(0.7)][index % 4],
         Double.random(in: 0...0.5))
    }

    var body: some View {
        GeometryReader { geometry in
            ForEach(pieces.indices, id: \.self) { index in
                let piece = pieces[index]
                RoundedRectangle(cornerRadius: 2)
                    .fill(piece.color)
                    .frame(width: 9, height: 6)
                    .rotationEffect(.degrees(fall ? piece.rotation : 0))
                    .position(x: piece.x * geometry.size.width + (fall ? piece.dx : 0), y: fall ? geometry.size.height + 20 : -12)
                    .animation(.timingCurve(0.2, 0.6, 0.4, 1, duration: 1.6).delay(piece.delay), value: fall)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { if !reduceMotion { fall = true } }
    }
}

#Preview {
    VStack(spacing: Spacing.l) {
        StreakNumber(value: 13)
        WeekHoneycomb(states: [.done, .done, .savedByHoneypot, .recordOnly, .rest, .today, .empty])
    }
    .padding()
}
