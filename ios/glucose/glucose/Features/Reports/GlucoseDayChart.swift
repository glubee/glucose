//
//  GlucoseDayChart.swift
//  glucose
//
//  하루 혈당 곡선 + 섭취 기록·인슐린 마커. 끊긴 구간은 선을 잇지 않는다:
//  값이 없는 칸이 있거나 두 값 사이가 15분보다 벌어지면 다른 선(series)으로 나눠 그린다.
//  세로축은 그날 값에 맞춰 정한다(리브레 원본의 50~350 고정 축은 곡선이 납작해 보여서).
//  크게 보기(GlucoseDayDetailView)에서는 시간을 확대하고 원하는 시각을 눌러 값과 기록을 확인한다.
//

import Charts
import SwiftUI

struct GlucosePoint: Identifiable {
    let time: Date
    let value: Int
    let segment: Int

    var id: Date { time }

    static let interval: TimeInterval = 15 * 60

    /// readings를 시각순 점으로 바꾸고, 끊긴 곳마다 segment 번호를 올린다.
    static func points(from readings: [GlucoseReadings.Reading], on day: Date, calendar: Calendar) -> [GlucosePoint] {
        var points: [GlucosePoint] = []
        var segment = 0
        var previousWasMissing = false

        let sorted = readings.compactMap { reading -> (Date, Int?)? in
            guard let time = time(of: reading.time, on: day, calendar: calendar) else { return nil }
            return (time, reading.value)
        }
        .sorted { $0.0 < $1.0 }

        for (time, value) in sorted {
            guard let value else {
                previousWasMissing = true
                continue
            }
            if let last = points.last, previousWasMissing || time.timeIntervalSince(last.time) > interval {
                segment += 1
            }
            points.append(GlucosePoint(time: time, value: value, segment: segment))
            previousWasMissing = false
        }
        return points
    }

    private static func time(of hhmm: String, on day: Date, calendar: Calendar) -> Date? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }
}

struct GlucoseDayChart: View {
    let day: Date
    let points: [GlucosePoint]
    let episodes: [DailyReport.Episode]
    let insulinEvents: [DailyReport.InsulinMarker]
    var height: CGFloat = 240
    /// 크게 보기에서만: 한 화면에 보이는 시간(nil = 하루 전체)
    var visibleHours: Int? = nil
    /// 크게 보기에서만: 누른 시각
    var selection: Binding<Date?>? = nil
    /// 크게 보기에서만: 확대했을 때 보이는 구간의 시작
    var scrollPosition: Binding<Date>? = nil
    /// 크게 보기에서만: 기록 표시 자리에 음식 사진을 보여준다
    var showsPhotos = false

    private var dayRange: ClosedRange<Date> {
        let start = ReportDay.calendar.startOfDay(for: day)
        let end = ReportDay.calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return start...end
    }

    private var isolatedPoints: [GlucosePoint] {
        let counts = Dictionary(grouping: points, by: \.segment).mapValues(\.count)
        return points.filter { counts[$0.segment] == 1 }
    }

    /// 그날 값에 맞춘 세로축: 아래는 70 이하까지, 위는 180 이상까지 보이게 하고 50 단위로 맞춘다
    static func yDomain(for points: [GlucosePoint]) -> ClosedRange<Int> {
        let values = points.map(\.value)
        guard let low = values.min(), let high = values.max() else { return 50...250 }
        let lower = max(40, min(70, (low - 10) / 10 * 10))
        let upper = min(400, max(200, Int((Double(high + 20) / 50).rounded(.up)) * 50))
        return lower...upper
    }

    private var yDomain: ClosedRange<Int> { Self.yDomain(for: points) }

    private var yMarks: [Int] {
        var marks = Array(stride(from: (yDomain.lowerBound + 49) / 50 * 50, through: yDomain.upperBound, by: 50))
        if yDomain.contains(70) && !marks.contains(70) { marks.append(70) }
        return marks.sorted()
    }

    private var marks: [DailyReport.Episode.IntakeMark] { episodes.flatMap(\.marks) }

    private var selectedPoint: GlucosePoint? {
        guard let time = selection?.wrappedValue else { return nil }
        return points.min { abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time)) }
            .flatMap { abs($0.time.timeIntervalSince(time)) <= GlucosePoint.interval ? $0 : nil }
    }

    var body: some View {
        let chart = Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("시각", point.time),
                    y: .value("혈당", point.value),
                    series: .value("구간", point.segment)
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Color.textPrimary)
            }

            // 앞뒤가 다 끊긴 단독 값은 선이 안 그려지므로 점으로 표시한다.
            ForEach(isolatedPoints) { point in
                PointMark(x: .value("시각", point.time), y: .value("혈당", point.value))
                    .symbolSize(16)
                    .foregroundStyle(Color.textPrimary)
            }

            ForEach(marks) { mark in
                RuleMark(x: .value("기록", mark.occurredAt))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(mark.context == .hypoTreatment ? Color.mintStrong : Color.brand)
                    .annotation(position: .top, spacing: 2) {
                        if showsPhotos, let photoId = mark.photoId {
                            FoodPhotoThumbnail(photoId: photoId, size: 30)
                        } else {
                            Image(systemName: mark.context.systemImage)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(mark.context == .hypoTreatment ? Color.mintStrong : Color.onBrandSoft)
                        }
                    }
            }

            ForEach(Array(insulinEvents.enumerated()), id: \.offset) { _, event in
                RuleMark(x: .value("인슐린", event.occurredAt))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [1, 2]))
                    .foregroundStyle(Color.insulin)
            }

            if let point = selectedPoint {
                RuleMark(x: .value("선택", point.time))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(Color.brand)
                PointMark(x: .value("선택", point.time), y: .value("혈당", point.value))
                    .symbolSize(70)
                    .foregroundStyle(Color.textPrimary)
                    .annotation(position: .top, spacing: 6,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 2) {
                            Text("\(point.value)")
                                .font(.pretendard(17, relativeTo: .headline, weight: .bold))
                            Text(ReportDay.timeString(from: point.time))
                                .font(.caption1)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(Color.canvas, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.line))
                    }
            }
        }
        .chartXScale(domain: dayRange)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: visibleHours.map { $0 <= 6 ? 1 : 3 } ?? 3)) { value in
                AxisGridLine().foregroundStyle(Color.line)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text("\(ReportDay.calendar.component(.hour, from: date))시")
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: yMarks) {
                AxisGridLine().foregroundStyle(Color.line)
                AxisValueLabel()
            }
        }
        .chartYAxisLabel("mg/dL", position: .topTrailing)
        .frame(height: height)

        Group {
            if let selection, let visibleHours, let scrollPosition {
                chart
                    .chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: TimeInterval(visibleHours * 3600))
                    .chartScrollPosition(x: scrollPosition)
                    .chartXSelection(value: selection)
            } else if let selection {
                chart.chartXSelection(value: selection)
            } else {
                chart
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("하루 혈당 곡선")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard let minValue = points.map(\.value).min(), let maxValue = points.map(\.value).max() else {
            return "값 없음"
        }
        return "최저 \(minValue), 최고 \(maxValue) mg/dL, 섭취 기록 \(marks.count)개, 인슐린 기록 \(insulinEvents.count)개"
    }
}
