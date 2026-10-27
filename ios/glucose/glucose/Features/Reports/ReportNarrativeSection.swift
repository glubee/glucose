import SwiftUI

/// 기본 리포트는 먼저 표시하고, 사용자가 요청할 때만 요약을 정리한다.
struct ReportNarrativeSection: View {
    let kind: String
    let date: String
    let summary: [String]
    @State private var narrative: ReportNarrative?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var requestID = UUID()

    var body: some View {
        Section("기록 요약") {
            if let narrative {
                ForEach(narrative.paragraphs.indices, id: \.self) { index in
                    Text(narrative.paragraphs[index].text)
                }
                DisclosureGroup("요약 근거") {
                    ForEach(narrative.facts) { fact in
                        LabeledContent(fact.label, value: fact.displayValue)
                    }
                }
                ForEach(narrative.limitations.indices, id: \.self) { index in
                    Text(narrative.limitations[index])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(summary.indices, id: \.self) { index in
                    Text(summary[index])
                }
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.secondary)
            }
            Button {
                Task { await generate() }
            } label: {
                HStack {
                    Text(narrative == nil ? "요약 정리하기" : "요약 다시 정리하기")
                    if isLoading { ProgressView() }
                }
            }
            .disabled(isLoading)
        }
        .onChange(of: date) { reset() }
        .onChange(of: summary) { reset() }
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
