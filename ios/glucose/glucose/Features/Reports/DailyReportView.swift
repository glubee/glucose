//
//  DailyReportView.swift
//  glucose
//
//  사실만 보여준다: 혈당이 어땠는지, 무엇을 언제 기록했는지. 인슐린 용량·식사량 조언은 하지 않는다.
//  판단에 필요한 데이터가 없으면 "아니다"가 아니라 "판단할 수 없다"고 표시한다.
//  v5: 큰 평균 숫자 + 데이터 칩 → 하루 흐름 카드 → 요약·음식 관찰 → 기록 묶음·인슐린 → 글루비 한마디.
//

import SwiftUI

struct DailyReportView: View {
    let viewModel: DailyReportViewModel
    @State private var showGraphUpload = false
    @State private var showChartDetail = false
    private let store = DayCloseStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                ReportPeriodNavigator(
                    title: ReportDay.displayString(from: viewModel.day),
                    previousLabel: "이전 날", nextLabel: "다음 날",
                    canGoForward: viewModel.canGoForward,
                    onPrevious: { Task { await viewModel.move(byDays: -1) } },
                    onNext: { Task { await viewModel.move(byDays: 1) } })

                switch viewModel.state {
                case .loading:
                    ReportLoadState(message: nil) {}
                case .failed(let message):
                    ReportLoadState(message: message) { Task { await viewModel.load() } }
                case .loaded(let report, let points):
                    if viewModel.requiresGraphReprocessing {
                        reprocessCard
                    } else {
                        glucoseHero(report: report)
                        chartCard(report: report, points: points)
                    }
                    if let story = report.story, !story.isEmpty {
                        DailyStoryCard(story: story, evidence: report.summary ?? [])
                        if let insights = report.insights, !insights.isEmpty {
                            DailyInsightsCard(insights: insights)
                        }
                    } else {
                        ReportNarrativeSection(kind: "DAILY", date: report.date, summary: report.summary ?? [])
                    }
                    FoodObservationSection(state: viewModel.foodAnalysis)
                    episodesCard(report.episodes, reboundThreshold: report.reboundGlucoseThreshold)
                    insulinCard(report: report)
                    educationCards(report.educationCards)
                    if store.isClosed(viewModel.day) {
                        ReportBeeNote(title: "이 날 하루를 완성했어요.")
                            .padding(.top, Spacing.xs)
                    }
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.l)
        }
        .background(Color.canvas)
        .refreshable { await viewModel.load() }
        .task(id: RecordChanges.shared.revision) { await viewModel.load() }
        .sheet(isPresented: $showGraphUpload) {
            GraphUploadView { uploadedDate in
                guard let date = ReportDay.date(fromAPIString: uploadedDate) else { return }
                Task { await viewModel.show(day: date) }
            }
        }
    }

    // MARK: - 평균 + 데이터 칩

    /// 예전 분석기 버전으로 읽은 그래프는 숨기고 다시 분석하게 한다(서버 GRAPH_REPROCESS_REQUIRED)
    private var reprocessCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "그래프를 다시 읽어야 해요")
            Text("이전에 읽은 수치를 확인해야 해서 잠시 숨겼어요. 저장된 원본으로 다시 분석할 수 있어요.")
                .font(.body2)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = viewModel.reprocessError {
                ReportNotes(lines: [error])
            }
            Button {
                Task { await viewModel.reprocessGraph() }
            } label: {
                if viewModel.isReprocessing {
                    HStack(spacing: Spacing.xs) { ProgressView().tint(Color.onButton); Text("다시 읽는 중") }
                } else {
                    Text("저장된 그래프 다시 읽기")
                }
            }
            .buttonStyle(.glubeePrimary)
            .disabled(viewModel.isReprocessing)
            Button("다른 원본 이미지 올리기") { showGraphUpload = true }
                .buttonStyle(.glubeeSecondary)
                .disabled(viewModel.isReprocessing)
        }
        .card(.brand)
    }

    @ViewBuilder
    private func glucoseHero(report: DailyReport) -> some View {
        if let glucose = report.glucose {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("평균 혈당")
                    .font(.pretendard(14, relativeTo: .subheadline, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                HStack(alignment: .center, spacing: Spacing.s) {
                    ReportBigNumber(value: ReportFormat.glucose(glucose.average))
                    Spacer(minLength: 0)
                    ReportDataChip(
                        text: glucose.sufficient == false
                            ? "일부만 읽혔어요 · \(ReportFormat.percent(glucose.coverageRatio))"
                            : "데이터 \(ReportFormat.percent(glucose.coverageRatio))",
                        tone: glucose.sufficient == false ? .limited : .sufficient)
                }
                HStack(spacing: Spacing.xs) {
                    ReportStatTile(title: "최저", value: glucose.min.map(String.init) ?? "–", unit: "mg/dL")
                    ReportStatTile(title: "최고", value: glucose.max.map(String.init) ?? "–", unit: "mg/dL")
                }
                ReportNotes(lines: ["근거: 15분 간격 \(glucose.readingsCount)칸 · 끊긴 구간은 비워 둬요."]
                            + (glucose.sufficient == false ? ["그래프가 일부만 읽혀 읽힌 구간의 수치만 보여드려요."] : []))
            }
        } else {
            VStack(spacing: Spacing.xs) {
                StateView(kind: .empty, title: "판단할 수 없어요",
                          message: "이 날의 혈당 그래프가 없어서\n읽힌 혈당값을 확인할 수 없어요.")
                Button {
                    showGraphUpload = true
                } label: {
                    Label("혈당 그래프 올리기", systemImage: "chart.xyaxis.line")
                }
                .buttonStyle(.glubeeAccent)
            }
            .card()
        }
    }

    // MARK: - 하루 흐름

    @ViewBuilder
    private func chartCard(report: DailyReport, points: [GlucosePoint]) -> some View {
        if report.glucose != nil {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "하루 흐름",
                              trailing: "식사 \(report.episodes.count) · 인슐린 \(report.insulinEventsCount)")
                if points.isEmpty {
                    Text("곡선을 불러오지 못했어요. 아래로 당겨 새로고침해주세요.")
                        .font(.body2)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    GlucoseDayChart(day: viewModel.day, points: points,
                                    episodes: report.episodes, insulinEvents: report.insulinEvents ?? [])
                        .contentShape(Rectangle())
                        .onTapGesture { showChartDetail = true }
                    ChartLegend()
                    Button {
                        showChartDetail = true
                    } label: {
                        Label("크게 보고 시각별로 확인하기", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.glubeeSecondary)
                }
            }
            .card()
            .fullScreenCover(isPresented: $showChartDetail) {
                GlucoseDayDetailView(day: viewModel.day, points: points, episodes: report.episodes,
                                     insulinEvents: report.insulinEvents ?? [])
            }
        }
    }

    // MARK: - 기록(에피소드)

    private func episodesCard(_ episodes: [DailyReport.Episode], reboundThreshold: Int?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "섭취 기록 묶음", trailing: "\(episodes.count)건")
            if episodes.isEmpty {
                Text("이 날 기록이 없어요.")
                    .font(.body2)
                    .foregroundStyle(Color.textSecondary)
            } else {
                ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                    if index > 0 { Divider().overlay(Color.line) }
                    EpisodeRow(episode: episode, reboundThreshold: reboundThreshold)
                }
            }
        }
        .card()
    }

    // MARK: - 인슐린

    private func insulinCard(report: DailyReport) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "인슐린 기록", trailing: "\(report.insulinEventsCount)건")
            if let events = report.insulinEvents, !events.isEmpty {
                ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                    HStack(spacing: Spacing.s) {
                        Image(systemName: "syringe")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.insulin)
                            .frame(width: 32, height: 32)
                            .background(Color.canvas, in: Circle())
                            .accessibilityHidden(true)
                        Text(ReportDay.timeString(from: event.occurredAt))
                            .font(.pretendard(16, relativeTo: .body, weight: .bold))
                            .monospacedDigit()
                        Text("\(event.units.formatted())단위 · \(event.kind)")
                            .font(.body2)
                            .foregroundStyle(Color.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color.textPrimary)
                    .accessibilityElement(children: .combine)
                }
            } else if report.insulinEventsCount == 0 {
                Text("이 날 인슐린 기록이 없어요.")
                    .font(.body2)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .card(.insulin)
    }

    // MARK: - 교육 카드(서버 고정 문구)

    @ViewBuilder
    private func educationCards(_ cards: [DailyReport.EducationCard]) -> some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "알아두면 좋아요", trailing: "고정 안내문")
                ForEach(cards) { card in
                    GuidanceCardContent(card: card)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.s)
                    .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.field))
                }
            }
            .card()
        }
    }
}

/// 곡선 아래 범례: 선 = 읽힌 혈당, 점선 = 기록 시각
private struct ChartLegend: View {
    var body: some View {
        HStack(spacing: Spacing.s) {
            item(Color.textPrimary, "읽힌 혈당", dashed: false)
            item(Color.brand, "음식 기록", dashed: true)
            item(Color.insulin, "인슐린", dashed: true)
            Spacer(minLength: 0)
        }
        .font(.caption1)
        .foregroundStyle(Color.textSecondary)
        .accessibilityHidden(true)
    }

    private func item(_ color: Color, _ title: String, dashed: Bool) -> some View {
        HStack(spacing: 4) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 1))
                path.addLine(to: CGPoint(x: 14, y: 1))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 2] : []))
            .frame(width: 14, height: 2)
            Text(title)
        }
    }
}

private struct EpisodeRow: View {
    let episode: DailyReport.Episode
    let reboundThreshold: Int?

    private var thresholdText: String {
        reboundThreshold.map { "\($0) mg/dL" } ?? "반동 기준"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.s) {
                Image(systemName: episode.effectiveContext.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(episode.effectiveContext == .hypoTreatment ? Color.mintStrong : Color.onBrandSoft)
                    .frame(width: 32, height: 32)
                    .background(episode.effectiveContext == .hypoTreatment ? Color.mintSoft : Color.brandSoft,
                                in: Circle())
                    .accessibilityHidden(true)
                Text(ReportDay.timeString(from: episode.startAt))
                    .font(.pretendard(16, relativeTo: .body, weight: .bold))
                    .monospacedDigit()
                Text(episode.effectiveContext.displayName)
                    .font(.body1)
                Spacer(minLength: 0)
                Text("기록 \(episode.intakeCount)건")
                    .font(.caption1)
                    .foregroundStyle(Color.textSecondary)
            }
            .foregroundStyle(Color.textPrimary)

            if let foods = episode.foods, !foods.isEmpty {
                Text(foods.joined(separator: ", "))
                    .font(.body2)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.leading, 32 + Spacing.s)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if episode.autoReclassified == true {
                note("직전 혈당이 낮아서 저혈당 처치로 분류했어요 (기록할 때: \(episode.originalContext.displayName))",
                     systemImage: "arrow.triangle.2.circlepath")
            }

            if episode.effectiveContext == .hypoTreatment {
                switch episode.reboundDetected {
                case .some(true):
                    note("처치 후 \(ReportDay.timeString(from: episode.windowEndAt))까지 \(thresholdText)을 넘는 값이 읽혔어요",
                         systemImage: "arrow.up.right")
                case .some(false):
                    note("처치 후 \(ReportDay.timeString(from: episode.windowEndAt))까지 읽힌 구간에서는 \(thresholdText)을 넘는 값이 없었어요",
                         systemImage: "info.circle")
                case .none:
                    note("처치 기록 뒤 구간에 읽힌 값이 없어 확인할 수 없어요", systemImage: "questionmark.circle")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func note(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption1)
            .foregroundStyle(Color.textSecondary)
            .padding(.leading, 44)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    NavigationStack {
        DailyReportView(viewModel: DailyReportViewModel())
    }
}
