#if DEBUG
import SwiftUI

/// 실제 홈 위에 미리보기를 열어 닫기 후 돌아갈 화면을 보장한다.
struct DebugReportFlow: View {
    let showsChart: Bool
    @State private var isPresented = true
    @State private var viewModel = DailyReportViewModel()

    var body: some View {
        RootTabView()
            .sheet(isPresented: $isPresented) {
                if showsChart {
                    let sample = ReportSamples.daily(ReportDay.today())
                    GlucoseDayDetailView(day: ReportDay.today(), points: sample.1, episodes: sample.0.episodes,
                                         insulinEvents: sample.0.insulinEvents ?? [])
                } else {
                    NavigationStack {
                        DailyReportView(viewModel: viewModel)
                            .navigationTitle("일일 리포트 미리보기")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("닫기") { isPresented = false }.accessibilityIdentifier("closeDailyReportPreview")
                                }
                            }
                    }
                }
            }
    }
}
#endif
