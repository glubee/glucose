import SwiftUI

struct ChartEventRecordDestination: View {
    let event: ChartEvent
    let onChanged: () async -> Void
    var body: some View {
        switch event.kind {
        case .intake(let mark):
            ReportRecordDestination(member: .init(id: event.id, mark: mark), onChanged: onChanged)
        case .insulin(let marker):
            InsulinChartRecordDestination(marker: marker, onChanged: onChanged)
        }
    }
}

private struct InsulinChartRecordDestination: View {
    let marker: DailyReport.InsulinMarker
    let onChanged: () async -> Void
    @State private var result: ReportInsulinRecordResolver.Resolution?
    @State private var failed = false
    @State private var attempt = 0
    @State private var showsRecords = false
    private var allowsEditing: Bool {
        #if DEBUG
        !ReportSamples.isEnabled
        #else
        true
        #endif
    }
    var body: some View {
        Group {
            if case .found(let item) = result {
                RecordDetailView(item: item, allowsEditing: allowsEditing, onChanged: onChanged)
            } else if result == nil && !failed {
                ProgressView("기록을 확인하고 있어요")
            } else {
                VStack(spacing: Spacing.s) {
                    Text(failed ? "기록을 불러오지 못했어요." : "일치하는 기록을 하나로 확인하지 못했어요. 전체 기록에서 확인해 주세요.")
                    Button("다시 확인") { attempt += 1 }.buttonStyle(.glubeeSecondary)
                    if allowsEditing { Button("전체 기록에서 찾기") { showsRecords = true }.buttonStyle(.glubeeSecondary) }
                }.padding(Spacing.gutter)
            }
        }
        .navigationTitle("인슐린 기록")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsRecords) { RecordsView() }
        .task(id: attempt) {
            result = nil
            failed = false
            #if DEBUG
            if ReportSamples.isEnabled {
                result = ReportSamples.insulinRecord(for: marker).map { .found(.insulin($0)) } ?? .missing
                return
            }
            #endif
            do {
                let resolved = try await ReportInsulinRecordResolver().resolve(marker)
                guard !Task.isCancelled else { return }
                result = resolved
            } catch {
                guard !Task.isCancelled else { return }
                failed = true
            }
        }
    }
}
