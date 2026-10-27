import SwiftUI

struct FoodObservationSection: View {
    let state: FoodAnalysisState

    @ViewBuilder
    var body: some View {
        switch state {
        case .loading:
            Section("음식과 혈당 관찰") { ProgressView("음식 기록을 확인하고 있어요") }
        case .failed:
            Section("음식과 혈당 관찰") {
                Text("음식별 관찰을 불러오지 못했어요. 아래로 당겨 다시 확인해주세요.")
                    .foregroundStyle(.secondary)
            }
        case .loaded(let report):
            if report.kind == "WEEKLY" {
                Section("반복된 음식 기록") {
                    if report.repeatedFoods.isEmpty {
                        Text("같은 음식 조합으로 반복 등록된 기록이 아직 없어요.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(report.repeatedFoods) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.foodNames).font(.headline)
                            Text(group.context.displayName).font(.caption).foregroundStyle(.secondary)
                            Text(group.summary)
                            if let low = group.minPeakDelta, let high = group.maxPeakDelta {
                                Text("관찰별 차이 범위: \(signed(low)) ~ \(signed(high)) mg/dL")
                                    .font(.caption).monospacedDigit()
                            }
                            DisclosureGroup("근거 기록 \(group.recordsCount)건") {
                                ForEach(report.observations.filter { group.intakeIds.contains($0.intakeId) }) { observation in
                                    FoodObservationRow(observation: observation, showDate: true)
                                }
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
                Section("이번 주 음식별 관찰") {
                    if report.observations.isEmpty {
                        Text("이번 주에 등록된 음식 기록이 없어요.").foregroundStyle(.secondary)
                    } else {
                        DisclosureGroup("전체 \(report.observations.count)건 보기") {
                            ForEach(report.observations) { observation in
                                FoodObservationRow(observation: observation, showDate: true)
                            }
                        }
                    }
                }
            } else {
                Section("음식별 혈당 관찰") {
                    if report.observations.isEmpty {
                        Text("이 날 등록된 음식 기록이 없어요.").foregroundStyle(.secondary)
                    }
                    ForEach(report.observations) { observation in
                        FoodObservationRow(observation: observation, showDate: false)
                    }
                }
            }
            Section {
                ForEach(report.limitations.indices, id: \.self) { index in
                    Text(report.limitations[index]).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }
}

private struct FoodObservationRow: View {
    let observation: FoodObservationReport.Observation
    let showDate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(observation.foodNames).font(.headline)
            HStack {
                if showDate { Text(ReportDay.displayString(from: observation.occurredAt)) }
                Text(ReportDay.timeString(from: observation.occurredAt))
                Text(observation.context.displayName)
                Spacer()
                Text(statusLabel)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(observation.summary)
            if let reading = observation.endReading {
                LabeledContent("구간 끝 근처 · \(ReportDay.timeString(from: reading.time))",
                               value: "\(reading.value) mg/dL")
                    .font(.caption).monospacedDigit()
            } else {
                LabeledContent("구간 끝 값", value: observation.status == "IN_PROGRESS" ? "아직 관찰 중" : "확인할 수 없음")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(observation.notes.indices, id: \.self) { index in
                Text(observation.notes[index]).font(.caption).foregroundStyle(.secondary)
            }
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
            .font(.caption)
        }
        .padding(.vertical, 6)
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
