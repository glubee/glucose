import SwiftUI

/// 기본 리포트는 먼저 표시하고, 사용자가 요청할 때만 요약을 정리한다. v5: 연노랑 카드
struct ReportNarrativeSection: View {
    let kind: String
    let date: String
    let summary: [String]
    @State private var narrative: ReportNarrative?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var requestID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "기록 요약", trailing: narrative == nil ? nil : "근거 기반 정리")
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(lines.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                        Circle().fill(Color.brand).frame(width: 6, height: 6)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text(lines[index])
                            .font(.body1)
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let narrative {
                DisclosureGroup("요약 근거") {
                    VStack(spacing: Spacing.xxs) {
                        ForEach(narrative.facts) { fact in
                            LabeledContent(fact.label, value: fact.displayValue)
                                .monospacedDigit()
                        }
                    }
                    .padding(.top, Spacing.xs)
                }
                .font(.caption1)
                .foregroundStyle(Color.textSecondary)
                .tint(Color.textPrimary)
                ReportNotes(lines: narrative.limitations)
            }
            if let errorMessage {
                ReportNotes(lines: [errorMessage])
            }
            Button {
                Task { await generate() }
            } label: {
                HStack(spacing: Spacing.xs) {
                    if isLoading { ProgressView().tint(Color.textPrimary) } else { Image(systemName: "sparkles") }
                    Text(narrative == nil ? "요약 정리하기" : "요약 다시 정리하기")
                }
            }
            .buttonStyle(.glubeeSecondary)
            .disabled(isLoading)
        }
        .card(.brand)
        .onChange(of: date) { reset() }
        .onChange(of: summary) { reset() }
    }

    private var lines: [String] {
        narrative.map { $0.paragraphs.map(\.text) } ?? summary
    }

    private func reset() {
        requestID = UUID()
        narrative = nil
        isLoading = false
        errorMessage = nil
    }

    @MainActor
    private func generate() async {
        let activeID = UUID()
        requestID = activeID
        isLoading = true
        errorMessage = nil
        do {
            let period = kind == "DAILY" ? "daily" : "weekly"
            let result: ReportNarrative = try await APIClient.shared.send(
                path: "/v1/reports/\(period)/\(date)/narrative", method: .post)
            guard requestID == activeID else { return }
            narrative = result
        } catch {
            guard requestID == activeID else { return }
            errorMessage = "요약을 정리하지 못했어요. 기록 요약은 그대로 확인할 수 있어요."
        }
        isLoading = false
    }
}
