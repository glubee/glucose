//
//  WeeklyOverlayChart.swift
//  glucose
//
//  주간 그래프 겹쳐 보기: 한 주의 일일 그래프를 0~24시 한 축에 겹쳐 그린다. 요일 버튼으로 하루만 진하게 볼 수 있다.
//  끊긴 구간은 잇지 않는다(GlucosePoint.segment). 세로축은 그 주 값에 맞춘다.
//

import Charts
import SwiftUI

struct WeeklyOverlayChart: View {
    /// 요일 순서(월~일)의 날짜와 그날 점들(그래프가 없으면 빈 배열)
    let days: [(date: Date, points: [GlucosePoint])]
    @Binding var selected: Date?

    /// 요일별 색(월~일). 진하게 볼 때만 이 색을 쓰고, 나머지는 옅게
    static let palette: [Color] = [
        Color(red: 0.91, green: 0.36, blue: 0.30), Color(red: 0.95, green: 0.62, blue: 0.20),
        Color(red: 0.80, green: 0.68, blue: 0.10), Color(red: 0.25, green: 0.66, blue: 0.45),
        Color(red: 0.20, green: 0.55, blue: 0.85), Color(red: 0.45, green: 0.38, blue: 0.85),
        Color(red: 0.80, green: 0.35, blue: 0.70),
    ]

    private struct Line: Identifiable {
        let id: String
        let dayIndex: Int
        let time: Date
        let value: Int
        let series: String
    }

    private var referenceDay: Date { ReportDay.calendar.startOfDay(for: days.first?.date ?? .now) }

    /// 날짜마다 시각을 기준일(주 첫날)로 옮겨 같은 0~24시 축에 놓는다
    private var lines: [Line] {
        days.enumerated().flatMap { index, day in
            day.points.map { point in
                let offset = point.time.timeIntervalSince(ReportDay.calendar.startOfDay(for: day.date))
                return Line(id: "\(index)-\(point.time.timeIntervalSince1970)", dayIndex: index,
                            time: referenceDay.addingTimeInterval(offset), value: point.value,
                            series: "\(index)-\(point.segment)")
            }
        }
    }

    private var selectedIndex: Int? {
        guard let selected else { return nil }
        return days.firstIndex { ReportDay.calendar.isDate($0.date, inSameDayAs: selected) }
    }

    private var yDomain: ClosedRange<Int> {
        GlucoseDayChart.yDomain(for: days.flatMap(\.points))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            dayPicker
            Chart {
                ForEach(lines) { line in
                    LineMark(x: .value("시각", line.time), y: .value("혈당", line.value), series: .value("날", line.series))
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: width(for: line.dayIndex), lineCap: .round, lineJoin: .round))
                        .foregroundStyle(color(for: line.dayIndex))
                }
            }
            .chartXScale(domain: referenceDay...referenceDay.addingTimeInterval(24 * 3600))
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                    AxisGridLine().foregroundStyle(Color.line)
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text("\(ReportDay.calendar.component(.hour, from: date))시")
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: Array(stride(from: (yDomain.lowerBound + 49) / 50 * 50,
                                                                   through: yDomain.upperBound, by: 50))) {
                    AxisGridLine().foregroundStyle(Color.line)
                    AxisValueLabel()
                }
            }
            .chartYAxisLabel("mg/dL", position: .topTrailing)
            .frame(height: 280)
            .animation(.easeInOut(duration: 0.2), value: selected)
            .accessibilityLabel("한 주 혈당 곡선 겹쳐 보기")

            Text(selectedIndex == nil ? "요일을 누르면 그날 곡선만 진하게 보여요." : "다시 누르면 전체로 돌아가요.")
                .font(.caption1)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var dayPicker: some View {
        HStack(spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                let isOn = selectedIndex == index
                let hasGraph = !day.points.isEmpty
                Button {
                    withAnimation(.snappy) { selected = isOn ? nil : day.date }
                } label: {
                    VStack(spacing: 2) {
                        Text(weekday(day.date))
                            .font(.body2.weight(isOn ? .bold : .semibold))
                        Circle()
                            .fill(hasGraph ? Self.palette[index % 7] : Color.line)
                            .frame(width: 6, height: 6)
                    }
                    .foregroundStyle(isOn ? Color.onButton : (hasGraph ? Color.textPrimary : Color.textSecondary))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(isOn ? Color.buttonFill : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!hasGraph)
                .accessibilityLabel("\(weekday(day.date))요일\(hasGraph ? "" : ", 그래프 없음")")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: 16))
    }

    private func color(for index: Int) -> Color {
        guard let selectedIndex else { return Self.palette[index % 7].opacity(0.85) }
        return index == selectedIndex ? Self.palette[index % 7] : Color.textSecondary.opacity(0.15)
    }

    private func width(for index: Int) -> CGFloat {
        guard let selectedIndex else { return 1.8 }
        return index == selectedIndex ? 3 : 1.2
    }

    private func weekday(_ date: Date) -> String {
        let symbols = ["일", "월", "화", "수", "목", "금", "토"]
        return symbols[ReportDay.calendar.component(.weekday, from: date) - 1]
    }
}
