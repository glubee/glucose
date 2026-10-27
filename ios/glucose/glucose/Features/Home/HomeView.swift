//
//  HomeView.swift
//  glucose
//
//  홈(v5): "민지님, 연속 12일" + 글루비 한마디 + 이번 주 벌집 + 꿀단지 + 오늘의 흐름,
//  아래에 노랑 "음식 찍기"(화면에서 유일한 노랑)와 "인슐린". 쉬어가는 중이면 쉬는 화면.
//

import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    @State private var showPhotoCapture = false
    @State private var showInsulin = false
    @State private var showRest = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.rest != nil {
                    restingContent
                } else {
                    content
                }
            }
            .background(Color.canvas)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if viewModel.rest == nil {
                            Button("쉬어가기", systemImage: "pause.circle") { showRest = true }
                        }
                        Button("하루 마무리", systemImage: "moon.stars") { openDayClose() }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundStyle(Color.textPrimary)
                    }
                    .accessibilityLabel("더 보기")
                }
            }
            .refreshable { await viewModel.refresh() }
            .task { await viewModel.refresh() }
            .sheet(isPresented: $showPhotoCapture, onDismiss: refresh) { PhotoCaptureView() }
            .sheet(isPresented: $showInsulin, onDismiss: refresh) { InsulinConfirmView() }
            .sheet(isPresented: $showRest) {
                RestSheet { reason, days in Task { await viewModel.startRest(reason, days: days) } }
            }
        }
    }

    private func refresh() { Task { await viewModel.refresh() } }

    private func openDayClose() {
        DeepLinkRouter.shared.handle(URL(string: "glubee://day-close")!)
    }

    // MARK: - 평소

    private var content: some View {
        let mood = viewModel.mood()
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        if !viewModel.nickname.isEmpty {
                            Text("\(viewModel.nickname)님,").font(.body1).foregroundStyle(Color.textSecondary)
                        } else {
                            Text("오늘의 흐름을\n함께 볼까요?").font(.headline1).foregroundStyle(Color.textPrimary)
                        }
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: Spacing.s) {
                                StreakNumber(value: viewModel.streak)
                                Text(mood.line)
                                    .font(.body2.weight(.semibold))
                                    .foregroundStyle(Color.onBrandSoft)
                                    .padding(.horizontal, Spacing.s)
                                    .padding(.vertical, Spacing.xs)
                                    .background(Color.brandSoft, in: Capsule())
                                    .accessibilityLabel("글루비: \(mood.line)")
                            }
                            Spacer(minLength: Spacing.s)
                            MascotView(pose: mood.pose, size: 110, floats: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.s) {
                        WeekHoneycomb(states: viewModel.weekStates)
                        if viewModel.honeypots > 0 {
                            Label("꿀단지 \(viewModel.honeypots)개 · 하루를 놓쳐도 연속을 지켜줘요",
                                  systemImage: "shippingbox.fill")
                                .font(.caption1)
                                .foregroundStyle(Color.onBrandSoft)
                                .padding(.horizontal, Spacing.s)
                                .padding(.vertical, Spacing.xxs)
                                .background(Color.brandSoft, in: Capsule())
                        }
                    }

                    todayFlowCard

                    if !viewModel.isTodayClosed && (viewModel.isPastDayClose() || viewModel.todayRecordCount > 0) {
                        Button("하루 마무리하기", action: openDayClose).buttonStyle(.glubeeSecondary)
                    }
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.m)
            }

            HStack(spacing: Spacing.s) {
                Button { showPhotoCapture = true } label: { Label("음식 찍기", systemImage: "camera.fill") }
                    .buttonStyle(.glubeeAccent)
                Button { showInsulin = true } label: { Label("인슐린", systemImage: "syringe.fill") }
                    .buttonStyle(.glubeeMuted)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.s)
        }
    }

    /// 오늘의 흐름: 그래프가 있으면 곡선, 없으면 오늘 기록만. 이 옆에는 글루비를 두지 않는다(평온 규칙)
    private var todayFlowCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("오늘의 흐름").font(.headline2).foregroundStyle(Color.textPrimary)
            switch viewModel.report.state {
            case .loaded(let report, let points) where !points.isEmpty:
                GlucoseDayChart(day: viewModel.today, points: points, episodes: report.episodes,
                                insulinEvents: report.insulinEvents ?? [])
                    .frame(height: 150)
            default:
                RoundedRectangle(cornerRadius: Radius.field)
                    .fill(Color.mintSoft)
                    .frame(height: 56)
                    .overlay(alignment: .leading) {
                        Text("70–180").font(.caption1).foregroundStyle(Color.mintStrong).padding(.leading, Spacing.s)
                    }
                    .accessibilityHidden(true)
                Text("밤에 리브레 그래프를 올리면 여기가 채워져요. 지금은 오늘 남긴 기록 \(viewModel.todayRecordCount)개만 보여요.")
                    .font(.body2)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .card(.plain)
    }

    // MARK: - 쉬어가는 중

    private var restingContent: some View {
        VStack(spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if !viewModel.nickname.isEmpty {
                    Text("\(viewModel.nickname)님,").font(.body1).foregroundStyle(Color.textSecondary)
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
            MascotView(pose: .breakTime, size: 180, floats: true)
            Text("천천히 와도 돼요").font(.headline1).foregroundStyle(Color.textPrimary)
            Text("쉬는 동안은 연속일이 줄지 않아요.\n알림도 보내지 않아요.")
                .font(.body2).foregroundStyle(Color.textSecondary).multilineTextAlignment(.center)
            WeekHoneycomb(states: viewModel.weekStates)
            Spacer()
            Button("다시 시작하기") { Task { await viewModel.endRest() } }.buttonStyle(.glubeeSecondary)
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, Spacing.m)
    }
}

/// 쉬어가기: 이유와 기간
private struct RestSheet: View {
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
