//
//  HomeView.swift
//  glucose
//
//  홈(디자이너 v5 프로토타입): "민지님, / 연속 N일"(숫자가 올라가며 나타남) + 노란 말풍선(한 글자씩) + 큰 글루비,
//  이번 주 벌집, 꿀단지, 오늘의 흐름 카드(기록 점), 아래에 음식 찍기·인슐린과 하루 마무리하기.
//  쉬어가는 중이면 쉬는 화면.
//

import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    @State private var showFoodSheet = false
    @State private var photoCapture: PhotoCaptureRequest?
    @State private var showInsulin = false
    @State private var shownStreak = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if viewModel.rest != nil {
                restingContent
            } else {
                content
            }
        }
        .background(Color.canvas)
        .task {
            await viewModel.refresh()
            countUp()
        }
        .sheet(isPresented: $showFoodSheet) {
            FoodRecordSheet { request in photoCapture = request }
        }
        .sheet(item: $photoCapture, onDismiss: refresh) { request in
            PhotoCaptureView(context: request.context, opensCamera: request.opensCamera)
        }
        .sheet(isPresented: $showInsulin, onDismiss: refresh) { InsulinConfirmView() }
    }

    private func refresh() { Task { await viewModel.refresh() } }

    private func openDayClose() {
        DeepLinkRouter.shared.handle(URL(string: "glubee://day-close")!)
    }

    /// 연속 숫자가 0부터 올라가며 나타난다
    private func countUp() {
        let target = viewModel.streak
        guard !reduceMotion, target > 0 else { shownStreak = target; return }
        shownStreak = 0
        withAnimation(.easeOut(duration: 0.7)) { shownStreak = target }
    }

    // MARK: - 평소

    private var content: some View {
        let mood = viewModel.mood()
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: Spacing.xs) {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(viewModel.nickname.isEmpty ? "오늘의 흐름을 함께 볼까요?" : "\(viewModel.nickname)님,")
                                .font(.pretendard(17, relativeTo: .headline, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                            StreakNumber(value: shownStreak)
                            TypingText(text: mood.line)
                                .font(.pretendard(14, relativeTo: .subheadline, weight: .semibold))
                                .foregroundStyle(Color.textPrimary)
                                .padding(.horizontal, Spacing.s)
                                .padding(.vertical, Spacing.xs)
                                .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 14))
                                .frame(maxWidth: 220, alignment: .leading)
                                .padding(.top, Spacing.xxs)
                                .accessibilityLabel("글루비: \(mood.line)")
                        }
                        Spacer(minLength: 0)
                        MascotView(pose: mood.pose, size: 132, motion: mood.motion, floats: true)
                    }

                    WeekHoneycomb(states: viewModel.weekStates)
                        .padding(.top, 14)

                    if viewModel.honeypots > 0 {
                        HStack(spacing: 6) {
                            HStack(spacing: 2) {
                                ForEach(0..<viewModel.honeypots, id: \.self) { _ in HoneypotIcon() }
                            }
                            Text("꿀단지 \(viewModel.honeypots)개 · 하루를 놓쳐도 연속을 지켜줘요")
                                .font(.pretendard(13, relativeTo: .footnote, weight: .semibold))
                                .foregroundStyle(Color.textPrimary)
                        }
                        .padding(.horizontal, Spacing.s)
                        .padding(.vertical, 7)
                        .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.field))
                        .padding(.top, Spacing.s)
                        .accessibilityElement(children: .combine)
                    }

                    todayFlowCard
                        .padding(.top, 14)
                }
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.m)
            }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button { showFoodSheet = true } label: { Label("음식 찍기", systemImage: "camera.fill") }
                        .buttonStyle(.glubeeAccent)
                    Button { showInsulin = true } label: { Label("인슐린", systemImage: "syringe.fill") }
                        .buttonStyle(.glubeeSoft)
                }
                if !viewModel.isTodayClosed {
                    Button("하루 마무리하기", action: openDayClose).buttonStyle(.glubeePrimary)
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
        }
    }

    /// 오늘의 흐름: 그래프가 있으면 곡선, 없으면 목표 범위 띠 + 오늘 기록 점.
    /// 이 옆에는 글루비를 두지 않는다(평온 규칙)
    private var todayFlowCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("오늘의 흐름").font(.pretendard(17, relativeTo: .headline, weight: .bold)).foregroundStyle(Color.textPrimary)
            switch viewModel.report.state {
            case .loaded(let report, let points) where !points.isEmpty:
                GlucoseDayChart(day: viewModel.today, points: points, episodes: report.episodes,
                                insulinEvents: report.insulinEvents ?? [])
                    .frame(height: 150)
            default:
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 6).fill(Color.mintSoft)
                            .frame(height: 40).offset(y: 24)
                        Rectangle().fill(Color.line).frame(height: 1).offset(y: 95)
                        ForEach(Array(viewModel.todayDots.enumerated()), id: \.offset) { _, dot in
                            Circle()
                                .fill(dot.isInsulin ? Color(red: 0xC9 / 255, green: 0xA6 / 255, blue: 0xE0 / 255) : Color.brand)
                                .frame(width: 12, height: 12)
                                .position(x: max(6, min(geometry.size.width - 6, geometry.size.width * dot.position)), y: 80)
                        }
                    }
                }
                .frame(height: 96)
                .accessibilityElement()
                .accessibilityLabel("오늘 그래프 없음, 기록 \(viewModel.todayRecordCount)개")
                Text("밤에 리브레 그래프를 올리면 여기가 채워져요. 지금은 오늘 남긴 기록 \(viewModel.todayRecordCount)개만 보여요.")
                    .font(.pretendard(14, relativeTo: .subheadline))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - 쉬어가는 중

    private var restingContent: some View {
        VStack(spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if !viewModel.nickname.isEmpty {
                    Text("\(viewModel.nickname)님,").font(.pretendard(17, relativeTo: .headline, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }
                StreakNumber(value: viewModel.streak).opacity(0.45)
                if let reason = viewModel.rest?.reason, let end = viewModel.restEndText {
                    Label("\(reason.title) · \(end)까지 멈춤", systemImage: "pause.fill")
                        .font(.caption1)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, Spacing.s)
                        .padding(.vertical, Spacing.xxs)
                        .background(Color.surfaceMuted, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
            MascotView(pose: .breakTime, size: 150, floats: true)
            Text("천천히 와도 돼요").font(.headline1).foregroundStyle(Color.textPrimary)
            Text("쉬는 동안은 연속일이 줄지 않아요.\n알림도 보내지 않아요.")
                .font(.body2).foregroundStyle(Color.textSecondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            WeekHoneycomb(states: viewModel.weekStates)
            Spacer()
            Button("다시 시작하기") { Task { await viewModel.endRest() } }.buttonStyle(.glubeeSoft)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
    }
}

/// 작은 꿀단지 아이콘
private struct HoneypotIcon: View {
    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1).fill(Color(red: 0.79, green: 0.54, blue: 0.23)).frame(width: 9, height: 3)
            RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.79, green: 0.54, blue: 0.23).opacity(0.85)).frame(width: 13, height: 12)
        }
        .accessibilityHidden(true)
    }
}

/// 쉬어가기: 이유와 기간(설정에서도 연다)
struct RestSheet: View {
    let onStart: (RestPeriod.Reason, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason: RestPeriod.Reason = .resting
    @State private var days = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            SheetHeader(title: "쉬어가기", subtitle: "쉬는 동안은 연속일이 끊기지도 늘지도 않고, 알림도 멈춰요.",
                        onClose: { dismiss() })
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("이유").font(.body2).foregroundStyle(Color.textSecondary)
                ChipPicker(options: RestPeriod.Reason.allCases.map { ($0, $0.title) }, selection: $reason)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("기간").font(.body2).foregroundStyle(Color.textSecondary)
                ChipPicker(options: [(1, "오늘만"), (3, "3일"), (7, "일주일")], selection: $days)
            }
            Spacer()
            Button("쉬어가기 시작") {
                onStart(reason, days)
                dismiss()
            }
            .buttonStyle(.glubeePrimary)
        }
        .padding(Spacing.gutter)
        .presentationDetents([.medium])
    }
}

#Preview {
    HomeView()
}
