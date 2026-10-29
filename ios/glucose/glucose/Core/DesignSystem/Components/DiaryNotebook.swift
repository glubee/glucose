//
//  DiaryNotebook.swift
//  glucose
//
//  "글루비와 쓰는 줄노트"(디자이너 하루 마무리 시안) 공통 조각. 홈 타임라인과 하루 마무리가 같이 쓴다.
//  줄 그은 종이, 왼쪽 시각 칸(시각 + 아침/점심/저녁), 점선 위에 붙인 폴라로이드 사진, 초록 밑줄 링크.
//

import SwiftUI

enum Diary {
    /// 왼쪽 시각 칸 너비
    static let timeColumn: CGFloat = 50
    /// 종이 줄 간격
    static let ruleSpacing: CGFloat = 36
    /// 링크·진행 막대·도장 색
    static let ink = Color.mintStrong

    /// 시각 아래 작은 이름. 식사는 때(아침·점심·저녁), 나머지는 상황 이름
    static func label(for time: Date, context: IntakeContext? = nil) -> String {
        if let context, context != .meal { return context.chipName }
        let hour = ReportDay.calendar.component(.hour, from: time)
        switch hour {
        case 4..<11: return "아침"
        case 11..<15: return "점심"
        case 15..<17: return "오후"
        case 17..<22: return "저녁"
        default: return "밤"
        }
    }
}

/// 줄 그은 종이 배경. 시각 칸 오른쪽에 옅은 세로 여백선
struct DiaryPaper: View {
    var marginX: CGFloat = Spacing.gutter + Diary.timeColumn / 2

    var body: some View {
        Canvas { context, size in
            var y = Diary.ruleSpacing
            while y < size.height {
                context.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                               with: .color(Color.line.opacity(0.45)), lineWidth: 0.6)
                y += Diary.ruleSpacing
            }
            context.stroke(Path { $0.move(to: CGPoint(x: marginX, y: 0)); $0.addLine(to: CGPoint(x: marginX, y: size.height)) },
                           with: .color(Diary.ink.opacity(0.22)), lineWidth: 1)
        }
        .background(Color.canvas)
        .accessibilityHidden(true)
    }
}

/// 시간줄 한 칸: 왼쪽 시각·때 이름, 점선, 내용
struct DiaryTimeRow<Content: View>: View {
    let time: Date?
    var label: String? = nil
    var dashed = true
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                if let time {
                    Text(ReportDay.timeString(from: time)).font(.caption1.monospacedDigit())
                }
                if let label {
                    Text(label).font(.caption1)
                }
            }
            .foregroundStyle(Color.textSecondary)
            .frame(width: Diary.timeColumn, alignment: .leading)
            .padding(.top, Spacing.l)
            .accessibilityElement(children: .combine)

            DiaryDashedRule(visible: dashed)
                .frame(width: 12)

            content
                .padding(.leading, Spacing.xs)
                .padding(.vertical, Spacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 사진 옆 세로 점선
struct DiaryDashedRule: View {
    var visible = true

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: CGPoint(x: geometry.size.width / 2, y: 0))
                path.addLine(to: CGPoint(x: geometry.size.width / 2, y: geometry.size.height))
            }
            .stroke(Diary.ink.opacity(visible ? 0.45 : 0), style: StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
        }
        .accessibilityHidden(true)
    }
}

/// 테이프로 붙인 폴라로이드 사진. 테두리 색으로 상황(식사·간식…)을 구분한다
struct DiaryPolaroid<Photo: View>: View {
    var tint: Color? = nil
    @ViewBuilder let photo: Photo

    var body: some View {
        photo
            .padding(5)
            .padding(.bottom, 9)
            .background(Color.white)
            .overlay(alignment: .bottom) {
                if let tint {
                    Rectangle().fill(tint).frame(height: 3).padding(.horizontal, 5).padding(.bottom, 3)
                }
            }
            .shadow(color: .black.opacity(0.12), radius: 3, y: 1.5)
            .overlay(alignment: .topLeading) { tape.offset(x: 10, y: -6) }
            .overlay(alignment: .bottomTrailing) { tape.frame(width: 22).offset(x: -6, y: 5) }
    }

    private var tape: some View {
        Rectangle()
            .fill(Color.mintSoft.opacity(0.9))
            .frame(width: 30, height: 11)
            .accessibilityHidden(true)
    }
}

/// 초록 밑줄 글자 링크("기록 보기 ›", "수정 ›")
struct DiaryLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(title) ›")
                .font(.body2)
                .underline()
                .foregroundStyle(Diary.ink)
                .frame(minHeight: Metrics.minTapTarget, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

/// 사진 없는 기록(글로 남긴 음식·인슐린)을 붙이는 작은 메모 카드
struct DiaryNoteCard<Content: View>: View {
    var tint: Color = .line
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.s)
            .background(Color.canvas, in: RoundedRectangle(cornerRadius: Radius.field))
            .overlay(RoundedRectangle(cornerRadius: Radius.field).strokeBorder(tint.opacity(0.6), lineWidth: 1))
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 0) {
            DiaryTimeRow(time: .now, label: "아침") {
                HStack(alignment: .top, spacing: Spacing.s) {
                    DiaryPolaroid(tint: IntakeContext.meal.tint) {
                        Color.brandSoft.frame(width: 112, height: 112)
                    }
                    VStack(alignment: .leading) {
                        Text("사과 · 우유").font(.body1)
                        DiaryLink(title: "기록 보기") {}
                    }
                }
            }
            DiaryTimeRow(time: .now, label: "저녁") {
                BeeSpeech(pose: .curious, text: "이 밖에 드신 것도 있나요?")
            }
        }
        .padding(.horizontal, Spacing.gutter)
    }
    .background(DiaryPaper())
}
