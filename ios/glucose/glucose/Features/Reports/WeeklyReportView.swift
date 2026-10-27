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
                    weekCard
                    recordsCard(report)
                    ReportNarrativeSection(kind: "WEEKLY", date: report.weekStart, summary: report.summary ?? [])
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
        .task { await viewModel.load() }
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
