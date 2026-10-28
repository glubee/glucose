//
//  ClinicianReportView.swift
//  glucose
//
//  진료용 리포트 시트: 기간을 고르면 서버가 정리한 사실을 보여주고, 같은 내용을 PDF로 공유한다.
//  PDF는 공유할 때만 임시 폴더에 만들고 시트를 닫으면 지운다(사진·그래프 원본은 넣지 않는다).
//

import SwiftUI

struct ClinicianReportView: View {
    @State private var viewModel = ClinicianReportViewModel()
    @State private var pdfURL: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SheetHeader(title: "진료용 리포트",
                            subtitle: "진료 때 의료진과 함께 볼 수 있게\n기록과 데이터의 한계만 정리해요.",
                            onClose: { dismiss() })

                ChipPicker(options: ClinicianReportViewModel.Period.allCases.map { ($0, $0.title) },
                           selection: $viewModel.period)

                switch viewModel.state {
                case .loading:
                    StateView(kind: .loading, title: "기록을 모으고 있어요")
                        .frame(minHeight: 240)
                case .failed(let message):
                    StateView(kind: .error, title: message, actionTitle: "다시 시도") {
                        Task { await viewModel.load() }
                    }
                    .card()
                case .loaded(let report):
                    ClinicianReportContent(report: report)
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.m)
        }
        .background(Color.canvas)
        .safeAreaInset(edge: .bottom) { shareBar }
        .task(id: viewModel.period) {
            removePDF()
            await viewModel.load()
            if case .loaded(let report) = viewModel.state {
                pdfURL = ClinicianPDF.make(report)
            }
        }
        .onDisappear { removePDF() }
    }

    @ViewBuilder
    private var shareBar: some View {
        if let pdfURL {
            ShareLink(item: pdfURL) {
                Label("PDF로 공유하기", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.glubeePrimary)
            .padding(.horizontal, Spacing.gutter)
            .padding(.top, Spacing.xs)
            .background(Color.canvas)
        }
    }

    private func removePDF() {
        if let pdfURL { try? FileManager.default.removeItem(at: pdfURL) }
        pdfURL = nil
    }
}

/// 화면용 본문: 합계 카드 → 날짜별 카드 → 참고 사항
private struct ClinicianReportContent: View {
    let report: ClinicianReport

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            totalsCard
            daysCard
            VStack(alignment: .leading, spacing: Spacing.xs) {
                SectionHeader(title: "참고 사항")
                ReportNotes(lines: report.notes + [report.disclaimer])
            }
            .card()
        }
    }

    private var totals: ClinicianReport.Totals { report.totals }

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(label: "\(ReportDay.displayString(fromAPIString: report.from)) – \(ReportDay.displayString(fromAPIString: report.to))",
                          title: "기간 평균 혈당")
            ReportBigNumber(value: ReportFormat.glucose(totals.average))
            HStack(spacing: Spacing.xs) {
                ReportStatTile(title: "최저", value: totals.min.map(String.init) ?? "–", unit: "mg/dL")
                ReportStatTile(title: "최고", value: totals.max.map(String.init) ?? "–", unit: "mg/dL")
            }
            FlowChips(items: [
                ("충분히 읽힘 \(totals.daysSufficient)일", .sufficient),
                ("일부만 읽힘 \(totals.daysLowCoverage)일", .limited),
                ("그래프 없음 \(totals.daysNoGraph)일", .none),
            ] + (totals.daysInProgress > 0 ? [("집계 중 \(totals.daysInProgress)일", .none)] : []))
            Divider().overlay(Color.line)
            countRow("\(report.lowReadingThreshold) mg/dL 미만으로 읽힌 값", totals.lowReadingCount, unit: "개")
            countRow("그래프 상단에 붙은 값", totals.aboveRangeCount, unit: "개")
            countRow("그래프 하단에 붙은 값", totals.belowRangeCount, unit: "개")
            countRow("섭취 기록 묶음 (저혈당 처치 \(totals.hypoTreatmentEpisodesCount))", totals.episodesCount, unit: "건")
            countRow("인슐린 기록", totals.insulinEventsCount, unit: "건")
        }
        .card()
    }

    private func countRow(_ title: String, _ value: Int, unit: String) -> some View {
        HStack {
            Text(title).font(.body2).foregroundStyle(Color.textSecondary)
            Spacer(minLength: Spacing.xs)
            Text("\(value)\(unit)")
                .font(.pretendard(15, relativeTo: .subheadline, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private var daysCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "날짜별", trailing: "\(report.days.count)일")
            ForEach(Array(report.days.reversed().enumerated()), id: \.element.id) { index, day in
                if index > 0 { Divider().overlay(Color.line) }
                DayRow(day: day)
            }
        }
        .card()
    }

    private struct DayRow: View {
        let day: ClinicianReport.Day

        private var tone: ReportDataChip.Tone {
            switch day.status {
            case "SUFFICIENT": .sufficient
            case "LOW_COVERAGE": .limited
            default: .none
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack {
                    Text(ReportDay.displayString(fromAPIString: day.date))
                        .font(.headline2)
                        .foregroundStyle(Color.textPrimary)
                    Spacer(minLength: Spacing.xs)
                    ReportDataChip(text: day.coverageRatio.map { "\(day.statusTitle) · \(ReportFormat.percent($0))" } ?? day.statusTitle,
                                   tone: tone)
                }
                if day.average != nil {
                    Text("평균 \(ReportFormat.glucose(day.average) ?? "–") · 최저 \(day.min.map(String.init) ?? "–") · 최고 \(day.max.map(String.init) ?? "–") mg/dL")
                        .font(.body2)
                        .monospacedDigit()
                        .foregroundStyle(Color.textPrimary)
                }
                Text(details)
                    .font(.caption1)
                    .foregroundStyle(Color.textSecondary)
            }
            .accessibilityElement(children: .combine)
        }

        private var details: String {
            var parts = ["섭취 \(day.episodes.count)건", "인슐린 \(day.insulinEvents.count)건"]
            if day.lowReadingCount > 0 { parts.insert("낮은 값 \(day.lowReadingCount)개", at: 0) }
            return parts.joined(separator: " · ")
        }
    }
}

/// 칩 여러 개를 줄바꿈하며 놓는다
private struct FlowChips: View {
    let items: [(String, ReportDataChip.Tone)]

    var body: some View {
        FlowLayout(spacing: Spacing.xxs) {
            ForEach(items.indices, id: \.self) { index in
                ReportDataChip(text: items[index].0, tone: items[index].1)
            }
        }
    }
}

/// 왼쪽부터 채우고 넘치면 다음 줄
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: .unspecified)
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var y: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

// MARK: - PDF

/// 인쇄용 화면(항상 라이트)을 A4 폭 한 장짜리 PDF로 만든다
enum ClinicianPDF {
    @MainActor
    static func make(_ report: ClinicianReport) -> URL? {
        let renderer = ImageRenderer(content: ClinicianPrintView(report: report)
            .frame(width: 595)
            .environment(\.colorScheme, .light))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("glubee-report-\(report.from)-\(report.to).pdf")
        var made = false
        renderer.render { size, render in
            var box = CGRect(origin: .zero, size: size)
            guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            render(context)
            context.endPDFPage()
            context.closePDF()
            made = true
        }
        return made ? url : nil
    }
}

private struct ClinicianPrintView: View {
    let report: ClinicianReport

    private var totals: ClinicianReport.Totals { report.totals }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("혈당 기록 요약 (진료 공유용)").font(.pretendard(20, relativeTo: .title, weight: .bold))
                Text("기간 \(report.from) ~ \(report.to) · 만든 날 \(ReportDay.apiString(from: report.generatedAt))")
                    .font(.pretendard(10, relativeTo: .caption))
                    .foregroundStyle(.gray)
            }

            section("기간 합계") {
                line("평균 / 최저 / 최고", "\(ReportFormat.glucose(totals.average) ?? "–") / \(totals.min.map(String.init) ?? "–") / \(totals.max.map(String.init) ?? "–") mg/dL")
                line("날짜 상태", "충분 \(totals.daysSufficient) · 일부 \(totals.daysLowCoverage) · 그래프 없음 \(totals.daysNoGraph) · 집계 중 \(totals.daysInProgress) (총 \(totals.periodDays)일)")
                line("읽힌 값", "\(totals.readingsCount)개 (15분 간격)")
                line("\(report.lowReadingThreshold) mg/dL 미만으로 읽힌 값", "\(totals.lowReadingCount)개")
                line("그래프 상단 / 하단에 붙은 값", "\(totals.aboveRangeCount) / \(totals.belowRangeCount)개")
                line("섭취 기록 묶음 (저혈당 처치)", "\(totals.episodesCount)건 (\(totals.hypoTreatmentEpisodesCount)건)")
                line("인슐린 기록", "\(totals.insulinEventsCount)건")
            }

            section("날짜별") {
                ForEach(report.days) { day in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(day.date).font(.pretendard(11, relativeTo: .body, weight: .bold))
                            Text(day.statusTitle + (day.coverageRatio.map { " · \(ReportFormat.percent($0))" } ?? ""))
                            Spacer()
                            if day.average != nil {
                                Text("평균 \(ReportFormat.glucose(day.average) ?? "–") · \(day.min.map(String.init) ?? "–")–\(day.max.map(String.init) ?? "–") mg/dL")
                            }
                        }
                        ForEach(dayLines(day), id: \.self) { text in
                            Text(text).foregroundStyle(.gray)
                        }
                    }
                    .font(.pretendard(10, relativeTo: .caption))
                    Divider()
                }
            }

            section("참고 사항") {
                ForEach(report.notes, id: \.self) { Text("· \($0)") }
                Text(report.disclaimer).bold()
            }
            .font(.pretendard(9, relativeTo: .caption))
        }
        .foregroundStyle(.black)
        .padding(36)
        .background(.white)
    }

    private func dayLines(_ day: ClinicianReport.Day) -> [String] {
        var lines: [String] = []
        if !day.lowReadings.isEmpty {
            lines.append("낮은 값: " + day.lowReadings.map { "\(ReportDay.timeString(from: $0.time)) \($0.value)" }.joined(separator: ", "))
        }
        for episode in day.episodes {
            var text = "\(ReportDay.timeString(from: episode.startAt)) \(episode.effectiveContext.displayName) \(episode.intakeCount)건"
            if episode.autoReclassified == true { text += " (입력: \(episode.enteredContext.displayName), 직전 값으로 처치 분류)" }
            if episode.effectiveContext == .hypoTreatment {
                switch episode.aboveReboundThresholdObserved {
                case .some(true): text += " · \(ReportDay.timeString(from: episode.windowEndAt))까지 \(report.reboundThreshold) 초과 값 읽힘"
                case .some(false): text += " · \(ReportDay.timeString(from: episode.windowEndAt))까지 \(report.reboundThreshold) 초과 값 없음"
                case .none: text += " · 뒤 구간 값 없음"
                }
            }
            lines.append(text)
        }
        if !day.insulinEvents.isEmpty {
            lines.append("인슐린: " + day.insulinEvents.map { "\(ReportDay.timeString(from: $0.occurredAt)) \($0.units.formatted())단위 \($0.kind)" }.joined(separator: ", "))
        }
        return lines
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.pretendard(13, relativeTo: .headline, weight: .bold))
            content()
        }
    }

    private func line(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.gray)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.pretendard(10, relativeTo: .caption))
    }
}
