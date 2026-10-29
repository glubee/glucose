//
//  WeeklyReportView.swift
//  glucose
//
//  주간 합계만 보여준다(숫자는 서버 계산). 그래프가 없는 날은 평균·반동 판단에서 빠지므로 그 날 수를 같이 보여준다.
//  v5: 큰 평균 숫자 + "그래프 있는 날" 칩 → 이번 주 벌집 → 기록 건수 → 요약·음식 관찰 → 글루비 한마디.
//

import SwiftUI

struct WeeklyReportView: View {
    let viewModel: WeeklyReportViewModel
    private let store = DayCloseStore.shared
    @State private var selectedDay: Date?

    private var weekStates: [HoneyCellState] { store.weekStates(containing: viewModel.weekStart) }

    private var completedDays: Int {
        weekStates.filter { $0 == .done || $0 == .recordOnly }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                ReportPeriodNavigator(
                    title: "\(ReportDay.displayString(from: viewModel.weekStart)) – \(ReportDay.displayString(from: viewModel.weekEnd))",
                    previousLabel: "이전 주", nextLabel: "다음 주",
                    canGoForward: viewModel.canGoForward,
                    onPrevious: { Task { await viewModel.move(byWeeks: -1) } },
                    onNext: { Task { await viewModel.move(byWeeks: 1) } })

                switch viewModel.state {
                case .loading:
                    ReportLoadState(message: nil) {}
                case .failed(let message):
                    ReportLoadState(message: message) { Task { await viewModel.load() } }
                case .loaded(let report):
                    glucoseHero(report)
                    overlayCard
                    if let story = report.story, !story.isEmpty {
                        DailyStoryCard(story: story, evidence: report.summary ?? [], title: "이번 주 이야기")
                    } else {
                        ReportNarrativeSection(kind: "WEEKLY", date: report.weekStart, summary: report.summary ?? [])
                    }
                    if let insights = report.insights, !insights.isEmpty {
                        insightsCard(insights)
                    }
                    if let days = report.days, !days.isEmpty {
                        daysCard(days)
                    }
                    if let bands = report.timeBands, bands.contains(where: { $0.average != nil }) {
                        timeBandsCard(bands)
                    }
                    weekCard
                    recordsCard(report)
                    FoodObservationSection(state: viewModel.foodAnalysis)
                    if completedDays > 0 {
                        ReportBeeNote(title: "이번 주에 하루를 \(completedDays)번 완성했어요.")
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
    }

    // MARK: - 한 주 겹쳐 보기

    @ViewBuilder
    private var overlayCard: some View {
        if viewModel.overlay.contains(where: { !$0.points.isEmpty }) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "한 주 겹쳐 보기",
                              trailing: "\(viewModel.overlay.filter { !$0.points.isEmpty }.count)일")
                WeeklyOverlayChart(days: viewModel.overlay, selected: $selectedDay)
            }
            .card()
        }
    }

    // MARK: - 요일별 한 줄

    private func daysCard(_ days: [WeeklyReport.Day]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "요일별로 보기", subtitle: "누르면 위 그래프에서 그날만 진하게 보여요.")
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                let date = ReportDay.date(fromAPIString: day.date)
                let isOn = isSelected(date)
                Button {
                    guard day.average != nil, let date else { return }
                    withAnimation(.snappy) { selectedDay = isOn ? nil : date }
                } label: {
                    HStack(spacing: Spacing.s) {
                        Circle().fill(day.average == nil ? Color.line : WeeklyOverlayChart.palette[index % 7])
                            .frame(width: 10, height: 10)
                        Text(date.map(ReportDay.displayString(from:)) ?? day.date)
                            .font(.body2.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                            .frame(width: 92, alignment: .leading)
                        if let average = day.average, let low = day.min, let high = day.max {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("평균 \(Int(average.rounded())) · \(low)~\(high)")
                                    .font(.body2.monospacedDigit())
                                    .foregroundStyle(Color.textPrimary)
                                Text(dayDetail(day))
                                    .font(.caption1)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        } else {
                            Text("그래프 없음").font(.body2).foregroundStyle(Color.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, Spacing.xxs)
                    .padding(.horizontal, Spacing.xs)
                    .background(isOn ? Color.brandSoft : Color.clear, in: RoundedRectangle(cornerRadius: Radius.field))
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    private func isSelected(_ date: Date?) -> Bool {
        guard let date, let selectedDay else { return false }
        return ReportDay.calendar.isDate(date, inSameDayAs: selectedDay)
    }

    private func dayDetail(_ day: WeeklyReport.Day) -> String {
        var parts = ["음식 \(day.intakeCount)", "인슐린 \(day.insulinCount)"]
        if day.lowCount > 0 { parts.append("70 미만 \(day.lowCount)번") }
        return parts.joined(separator: " · ")
    }

    // MARK: - 시간대별

    private func timeBandsCard(_ bands: [WeeklyReport.TimeBand]) -> some View {
        let maxValue = Double(bands.compactMap(\.max).max() ?? 250)
        return VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "시간대별 평균", subtitle: "막대는 그 시간대에 읽힌 가장 낮은 값부터 가장 높은 값까지예요.")
            ForEach(bands) { band in
                HStack(spacing: Spacing.s) {
                    Text(band.label)
                        .font(.caption1.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 84, alignment: .leading)
                    if let average = band.average, let low = band.min, let high = band.max {
                        GeometryReader { geometry in
                            let width = geometry.size.width
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.surfaceMuted).frame(height: 10)
                                Capsule().fill(Color.brandSoft)
                                    .frame(width: max(8, width * CGFloat(Double(high - low) / maxValue)), height: 10)
                                    .offset(x: width * CGFloat(Double(low) / maxValue))
                                Circle().fill(Color.textPrimary).frame(width: 10, height: 10)
                                    .offset(x: width * CGFloat(average / maxValue) - 5)
                            }
                        }
                        .frame(height: 12)
                        Text("\(Int(average.rounded()))")
                            .font(.body2.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                            .frame(width: 36, alignment: .trailing)
                    } else {
                        Text("값 없음").font(.caption1).foregroundStyle(Color.textSecondary)
                        Spacer()
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    // MARK: - 흐름 안내 모음

    private func insightsCard(_ insights: [WeeklyReport.InsightCount]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "이번 주에 보인 흐름", trailing: "검토 전 안내")
            ForEach(insights) { insight in
                HStack(alignment: .firstTextBaseline) {
                    Label(insight.title, systemImage: "lightbulb")
                        .font(.body2)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text("\(insight.days)일")
                        .font(.body2.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                }
                Text(insight.dates.compactMap { ReportDay.date(fromAPIString: $0) }
                    .map(ReportDay.displayString(from:)).joined(separator: ", "))
                    .font(.caption1)
                    .foregroundStyle(Color.textSecondary)
            }
            Text("자세한 설명은 그 날의 일일 리포트에 있어요. 일반적인 정보이며 진단이 아니에요.")
                .font(.caption1)
                .foregroundStyle(Color.textSecondary)
        }
        .card()
    }

    // MARK: - 평균 + 데이터 칩

    private func glucoseHero(_ report: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("이번 주 평균 혈당")
                .font(.pretendard(14, relativeTo: .subheadline, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
            HStack(alignment: .center, spacing: Spacing.s) {
                ReportBigNumber(value: ReportFormat.glucose(report.averageGlucose))
                Spacer(minLength: 0)
                ReportDataChip(text: "그래프 있는 날 \(report.daysWithData)/7일",
                               tone: report.daysWithData == 0 ? .none
                                   : (report.lowCoverageDays ?? 0) > 0 || report.daysInsufficient > 0 ? .limited : .sufficient)
            }
            if report.averageGlucose == nil {
                Text("이번 주는 혈당 그래프가 없어서 판단할 수 없어요.")
                    .font(.body2)
                    .foregroundStyle(Color.textSecondary)
            }
            ReportNotes(lines: dataNotes(report))
        }
    }

    private func dataNotes(_ report: WeeklyReport) -> [String] {
        var lines: [String] = []
        if let sufficient = report.sufficientDays, let limited = report.lowCoverageDays {
            lines.append("지난 날 중 충분히 읽힌 날 \(sufficient)일 · 일부만 읽힌 날 \(limited)일")
        }
        if let pending = report.pendingDays, pending > 0 {
            lines.append("오늘과 이후 \(pending)일은 집계 중이에요.")
        }
        return lines
    }

    // MARK: - 이번 주 벌집(기기에 저장된 하루 완성 기록)

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "하루 완성", trailing: "\(completedDays)일")
            WeekHoneycomb(states: weekStates)
        }
        .card(.brand)
    }

    // MARK: - 기록 건수

    private func recordsCard(_ report: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "기록")
            HStack(spacing: Spacing.xs) {
                ReportStatTile(title: "섭취 묶음", value: "\(report.episodesCount)", unit: "건")
                ReportStatTile(title: "인슐린", value: "\(report.insulinEventsCount)", unit: "건")
            }
            ReportStatTile(title: "처치 기록 뒤 그래프 상단 표시", value: "\(report.reboundCount)", unit: "건")
            if report.daysInsufficient > 0 {
                ReportNotes(lines: ["그래프가 없는 지난 \(report.daysInsufficient)일은 그래프 상단 표시 건수에 포함하지 않았어요."])
            }
        }
        .card()
    }
}

#Preview {
    NavigationStack {
        WeeklyReportView(viewModel: WeeklyReportViewModel())
    }
}
