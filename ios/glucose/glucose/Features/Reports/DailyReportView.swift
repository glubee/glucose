//
//  DailyReportView.swift
//  glucose
//
//  사실만 보여준다: 혈당이 어땠는지, 무엇을 언제 기록했는지. 인슐린 용량·식사량 조언은 하지 않는다.
//  판단에 필요한 데이터가 없으면 "아니다"가 아니라 "판단할 수 없다"고 표시한다.
//  평균·데이터 칩 → 하루 흐름(사진이 붙은 그래프 + 시각순 기록) → 하루 이야기 → 흐름 안내 → 음식 관찰.
//

import SwiftUI

struct DailyReportView: View {
    let viewModel: DailyReportViewModel
    @State private var showGraphUpload = false
    @State private var chartDetail: ChartDetailSnapshot?
    @State private var selectedPhoto: ChartPhotoGroup?

    private struct ChartDetailSnapshot: Identifiable {
        let id = UUID()
        let day: Date
        let report: DailyReport
        let points: [GlucosePoint]
    }
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
                    // v5 순서(Dave 2026-10-29): 평균 혈당 → 그래프(시각별 확인) → 하루 이야기 → 흐름 안내.
                    // "섭취 기록 묶음 n건"·인슐린 목록 카드는 그래프 아래 "이날 기록"(시각순)으로 대신한다.
                    if viewModel.requiresGraphReprocessing {
                        reprocessCard
                    } else {
                        glucoseHero(report: report)
                    }
                    chartCard(report: report, points: viewModel.requiresGraphReprocessing ? [] : points)
                    if let story = report.story, !story.isEmpty {
                        DailyStoryCard(story: story, evidence: report.summary ?? [])
                    } else {
                        ReportNarrativeSection(kind: "DAILY", date: report.date, summary: report.summary ?? [])
                    }
                    if let insights = report.insights, !insights.isEmpty {
                        DailyInsightsCard(insights: insights)
                    }
                    FoodObservationSection(state: viewModel.foodAnalysis)
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
        .accessibilityIdentifier("dailyReportContent")
        .background(Color.canvas)
        .refreshable { await viewModel.load() }
        .task(id: RecordChanges.shared.revision) { await viewModel.load() }
        .onChange(of: viewModel.day) { _, _ in closePhotoScreens() }
        .onChange(of: RecordChanges.shared.revision) { _, _ in closePhotoScreens() }
        .sheet(item: $selectedPhoto) { group in
            ReportPhotoGallery(group: group) { closePhotoScreens() }
        }
        .fullScreenCover(item: $chartDetail) { snapshot in
            GlucoseDayDetailView(day: snapshot.day, points: snapshot.points, episodes: snapshot.report.episodes,
                                 insulinEvents: snapshot.report.insulinEvents ?? []) { closePhotoScreens() }
        }
        .sheet(isPresented: $showGraphUpload) {
            GraphUploadView { uploadedDate in
                guard let date = ReportDay.date(fromAPIString: uploadedDate) else { return }
                Task { await viewModel.show(day: date) }
            }
        }
    }

    private var isPreview: Bool {
        #if DEBUG
        ReportSamples.isEnabled
        #else
        false
        #endif
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
            .disabled(viewModel.isReprocessing || isPreview)
            Button("다른 원본 이미지 올리기") { showGraphUpload = true }
                .buttonStyle(.glubeeSecondary)
                .disabled(viewModel.isReprocessing || isPreview)
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
        if report.glucose != nil || report.episodes.flatMap(\.marks).contains(where: { $0.photoId != nil }) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    SectionHeader(title: "하루 흐름")
                    Button {
                        chartDetail = ChartDetailSnapshot(day: viewModel.day, report: report, points: points)
                    } label: {
                        Label("크게 보기", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.caption1.weight(.semibold))
                    }
                    .accessibilityIdentifier("openChartDetail")
                    .foregroundStyle(Color.textPrimary)
                    .frame(minHeight: Metrics.minTapTarget)
                    .disabled(points.isEmpty)
                }
                if points.isEmpty {
                    Text("읽힌 혈당값이 없어 곡선을 표시할 수 없어요.")
                        .font(.body2).foregroundStyle(Color.textSecondary)
                    ChartPhotoTimeline(groups: ChartPhotoGroup.make(marks: report.episodes.flatMap(\.marks),
                                                                    day: viewModel.day, points: points)) {
                        selectedPhoto = $0
                    }
                } else {
                    DayChartExplorer(day: viewModel.day, points: points,
                                     episodes: report.episodes, insulinEvents: report.insulinEvents ?? [],
                                     chartHeight: 300, onSelectPhoto: { selectedPhoto = $0 })
                }
            }
            .card()
        }
    }

    private func closePhotoScreens() {
        selectedPhoto = nil
        chartDetail = nil
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


#Preview {
    NavigationStack {
        DailyReportView(viewModel: DailyReportViewModel())
    }
}
