//
//  ReportsView.swift
//  glucose
//
//  일일/주간 전환. 뷰모델을 여기서 들고 있어서 전환해도 보던 날짜·주가 유지된다.
//  v5: 큰 제목 "리포트" + 캡슐 전환, 오른쪽 위 전체 기록, 전환 옆 진료용 리포트.
//

import SwiftUI

struct ReportsView: View {
    private enum Mode: String, CaseIterable {
        case daily = "일일"
        case weekly = "주간"
    }

    @State private var mode: Mode = Self.initialMode
    @State private var dailyViewModel = DailyReportViewModel()
    @State private var weeklyViewModel = WeeklyReportViewModel()
    /// 기록 탭과 같은 전체 목록을 시트에서도 연다
    @State private var showRecords = false
    @State private var showClinician = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.s) {
                header
                    .padding(.horizontal, Spacing.gutter)
                switch mode {
                case .daily:
                    DailyReportView(viewModel: dailyViewModel)
                case .weekly:
                    WeeklyReportView(viewModel: weeklyViewModel)
                }
            }
            .background(Color.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showRecords) { RecordsView() }
            .sheet(isPresented: $showClinician) { ClinicianReportView() }
        }
    }

    private static var initialMode: Mode {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-weekly") { return .weekly }
        #endif
        return .daily
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .center) {
                Text("리포트")
                    .font(.pretendard(32, relativeTo: .largeTitle, weight: .bold))
                    .tracking(-1)
                    .foregroundStyle(Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { showRecords = true } label: {
                    Image(systemName: "list.bullet")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(Color.surfaceMuted, in: Circle())
                        .frame(width: Metrics.minTapTarget, height: Metrics.minTapTarget)
                }
                .accessibilityLabel("전체 기록")
            }
            .padding(.top, Spacing.xs)

            HStack(spacing: Spacing.xs) {
                ModeSwitch(selection: $mode)
                Spacer(minLength: 0)
                Button { showClinician = true } label: {
                    Label("진료용", systemImage: "stethoscope")
                        .font(.pretendard(14, relativeTo: .subheadline, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, Spacing.s)
                        .frame(height: 36)
                        .overlay(Capsule().strokeBorder(Color.line, lineWidth: 1))
                        .frame(minHeight: Metrics.minTapTarget)
                }
                .accessibilityLabel("진료용 리포트 만들기")
            }
        }
    }

    /// v5 프로토타입의 회색 캡슐 전환(선택된 쪽만 흰 캡슐)
    private struct ModeSwitch: View {
        @Binding var selection: Mode
        @Namespace private var namespace

        var body: some View {
            HStack(spacing: 2) {
                ForEach(Mode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.spring(duration: 0.3)) { selection = mode }
                    } label: {
                        Text(mode.rawValue)
                            .font(.pretendard(15, relativeTo: .subheadline, weight: selection == mode ? .bold : .medium))
                            .foregroundStyle(selection == mode ? Color.textPrimary : Color.textSecondary)
                            .frame(width: 64, height: 34)
                            .background {
                                if selection == mode {
                                    Capsule()
                                        .fill(Color.canvas)
                                        .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                                        .matchedGeometryEffect(id: "mode", in: namespace)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == mode ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Color.surfaceMuted, in: Capsule())
        }
    }
}

#Preview {
    ReportsView()
}
