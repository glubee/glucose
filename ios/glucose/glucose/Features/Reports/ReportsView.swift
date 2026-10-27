//
//  ReportsView.swift
//  glucose
//
//  일일/주간 전환. 뷰모델을 여기서 들고 있어서 전환해도 보던 날짜·주가 유지된다.
//

import SwiftUI

struct ReportsView: View {
    private enum Mode: String, CaseIterable {
        case daily = "일일"
        case weekly = "주간"
    }

    @State private var mode: Mode = .daily
    @State private var dailyViewModel = DailyReportViewModel()
    @State private var weeklyViewModel = WeeklyReportViewModel()
    /// 기록 탭이 없어져서(v5 탭: 홈·리포트·리뷰·설정) 지난 기록 목록은 여기서 연다
    @State private var showRecords = false

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .daily:
                    DailyReportView(viewModel: dailyViewModel)
                case .weekly:
                    WeeklyReportView(viewModel: weeklyViewModel)
                }
            }
            .navigationTitle("리포트")
            .sheet(isPresented: $showRecords) { RecordsView() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("전체 기록") { showRecords = true }
                }
                ToolbarItem(placement: .principal) {
                    Picker("보기", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ReportsView()
}
