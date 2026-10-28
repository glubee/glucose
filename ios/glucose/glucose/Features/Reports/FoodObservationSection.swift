import SwiftUI

/// v5: 카드로 묶는다. 일일 = 음식별 관찰 카드, 주간 = 반복된 음식 카드 + 전체 관찰 카드
struct FoodObservationSection: View {
    let state: FoodAnalysisState

    var body: some View {
        switch state {
        case .loading:
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "음식과 혈당 관찰")
                HStack(spacing: Spacing.xs) {
                    ProgressView().tint(Color.textSecondary)
                    Text("음식 기록을 확인하고 있어요").font(.body2).foregroundStyle(Color.textSecondary)
                }
            }
            .card()
        case .failed:
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "음식과 혈당 관찰")
                Text("음식별 관찰을 불러오지 못했어요. 아래로 당겨 다시 확인해주세요.")
                    .font(.body2).foregroundStyle(Color.textSecondary)
            }
            .card()
        case .loaded(let report):
            if report.kind == "WEEKLY" {
                weekly(report)
            } else {
                daily(report)
            }
        }
    }

    private func daily(_ report: FoodObservationReport) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "음식별 혈당 관찰", trailing: "\(report.observations.count)건")
            if report.observations.isEmpty {
                Text("이 날 등록된 음식 기록이 없어요.").font(.body2).foregroundStyle(Color.textSecondary)
            }
            ForEach(Array(report.observations.enumerated()), id: \.element.id) { index, observation in
                if index > 0 { Divider().overlay(Color.line) }
                FoodObservationRow(observation: observation, showDate: false)
            }
            ReportNotes(lines: report.limitations)
        }
        .card()
    }

    @ViewBuilder
    private func weekly(_ report: FoodObservationReport) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "반복된 음식 기록", trailing: "\(report.repeatedFoods.count)가지")
            if report.repeatedFoods.isEmpty {
                Text("같은 음식 조합으로 반복 등록된 기록이 아직 없어요.")
                    .font(.body2).foregroundStyle(Color.textSecondary)
            }
            ForEach(report.repeatedFoods) { group in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(group.foodNames).font(.headline2).foregroundStyle(Color.textPrimary)
                        Spacer(minLength: Spacing.xs)
                        Text(group.context.displayName).font(.caption1).foregroundStyle(Color.textSecondary)
                    }
                    Text(group.summary).font(.body2).foregroundStyle(Color.textPrimary)
                    if let low = group.minPeakDelta, let high = group.maxPeakDelta {
                        Text("관찰별 차이 범위: \(signed(low)) ~ \(signed(high)) mg/dL")
                            .font(.caption1).monospacedDigit().foregroundStyle(Color.textSecondary)
                    }
                    DisclosureGroup("근거 기록 \(group.recordsCount)건") {
                        ForEach(report.observations.filter { group.intakeIds.contains($0.intakeId) }) { observation in
                            FoodObservationRow(observation: observation, showDate: true)
                                .padding(.top, Spacing.xs)
                        }
                    }
                    .font(.body2.weight(.semibold))
                    .tint(Color.textPrimary)
                }
                .padding(Spacing.s)
                .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.field))
            }
        }
        .card()

        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "이번 주 음식별 관찰", trailing: "\(report.observations.count)건")
            if report.observations.isEmpty {
                Text("이번 주에 등록된 음식 기록이 없어요.").font(.body2).foregroundStyle(Color.textSecondary)
            } else {
                DisclosureGroup("전체 보기") {
                    ForEach(report.observations) { observation in
                        FoodObservationRow(observation: observation, showDate: true)
                            .padding(.top, Spacing.s)
                    }
                }
                .font(.body2.weight(.semibold))
                .tint(Color.textPrimary)
            }
            ReportNotes(lines: report.limitations)
        }
        .card()
    }

    private func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }
}

private struct FoodObservationRow: View {
    let observation: FoodObservationReport.Observation
    let showDate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(observation.foodNames).font(.headline2).foregroundStyle(Color.textPrimary)
                Spacer(minLength: Spacing.xs)
                ReportDataChip(text: statusLabel, tone: statusTone)
            }
            HStack(spacing: Spacing.xxs) {
                if showDate { Text(ReportDay.displayString(from: observation.occurredAt)) }
                Text(ReportDay.timeString(from: observation.occurredAt))
                Text("· \(observation.context.displayName)")
            }
            .font(.caption1)
            .monospacedDigit()
            .foregroundStyle(Color.textSecondary)
            Text(observation.summary).font(.body2).foregroundStyle(Color.textPrimary)
            if let reading = observation.endReading {
                LabeledContent("구간 끝 근처 · \(ReportDay.timeString(from: reading.time))",
                               value: "\(reading.value) mg/dL")
                    .font(.caption1).monospacedDigit().foregroundStyle(Color.textPrimary)
            } else {
                LabeledContent("구간 끝 값", value: observation.status == "IN_PROGRESS" ? "아직 관찰 중" : "확인할 수 없음")
                    .font(.caption1).foregroundStyle(Color.textSecondary)
            }
            ReportNotes(lines: observation.notes)
            DisclosureGroup("관찰 근거") {
                if let baseline = observation.baseline {
                    LabeledContent("기록 직전 · \(ReportDay.timeString(from: baseline.time))", value: "\(baseline.value) mg/dL")
                } else {
                    LabeledContent("기록 직전 값", value: "확인할 수 없음")
                }
                if let peak = observation.peak {
                    LabeledContent("읽힌 최고 · \(ReportDay.timeString(from: peak.time))", value: "\(peak.value) mg/dL")
                } else {
                    LabeledContent("읽힌 최고", value: "확인할 수 없음")
                }
                LabeledContent("읽힌 구간", value: "\(observation.readingsCount) / \(observation.expectedReadingsCount)칸")
                LabeledContent("관찰 구간", value: "\(observation.windowMinutes)분")
                if observation.clippedReadingsCount > 0 {
                    LabeledContent("경계에 붙은 값", value: "\(observation.clippedReadingsCount)개")
                }
            }
            .font(.caption1)
            .foregroundStyle(Color.textSecondary)
            .tint(Color.textPrimary)
        }
    }

    private var statusTone: ReportDataChip.Tone {
        switch observation.status {
        case "OBSERVED": .sufficient
        case "LIMITED": .limited
        default: .none
        }
    }

    private var statusLabel: String {
        switch observation.status {
        case "IN_PROGRESS": return "관찰 중"
        case "UNAVAILABLE": return "자료 부족"
        case "LIMITED": return "일부 제한"
        case "OBSERVED": return "기록 관찰"
        default: return "자료 확인"
        }
    }
}
