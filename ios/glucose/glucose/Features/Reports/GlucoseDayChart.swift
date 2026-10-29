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
            return (time, reading.flag == "MISSING" ? nil : reading.value)
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
        let parts = hhmm.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy { "0123456789".contains($0) } }),
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
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
    var visibleDuration: TimeInterval? = nil
    /// 크게 보기에서만: 누른 시각
    var selection: Binding<Date?>? = nil
    /// 크게 보기에서만: 확대했을 때 보이는 구간의 시작
    var scrollPosition: Binding<Date>? = nil
    /// 일일 리포트·크게 보기: 곡선 부근 사진과 아래 기록 줄을 보여준다
    var showsPhotos = false
    var onSelectPhoto: ((ChartPhotoGroup) -> Void)? = nil
    var eventSelection: Binding<String?>? = nil
    var onSelectEventCluster: ((ChartEventCluster) -> Void)? = nil
    /// 선택한 값을 그래프 안 말풍선으로 보여줄지. 그래프 밖 띠로 보여주는 화면(DayChartExplorer)은 끈다(사진에 가리지 않게)
    var showsSelectionCallout = true
    /// 끌기 대신 눌러서 시각을 고른다. 리포트 안에서 그래프 위를 세로로 끌어도 화면이 스크롤되게 한다
    var selectsByTap = false

    private var dayRange: ClosedRange<Date> {
        let start = ReportDay.calendar.startOfDay(for: day)
        let end = ReportDay.calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return start...end
    }

    private var displayDuration: TimeInterval { visibleDuration ?? TimeInterval((visibleHours ?? 24) * 3600) }
    private var visibleRange: ClosedRange<Date> {
        let start = displayDuration >= 86_400 ? dayRange.lowerBound : (scrollPosition?.wrappedValue ?? dayRange.lowerBound)
        return start...start.addingTimeInterval(displayDuration)
    }
    private var events: [ChartEvent] { ChartEvent.make(day: day, episodes: episodes, insulinEvents: insulinEvents) }
    private func eventOpacity(_ id: String) -> Double {
        guard let eventSelection else { return 1 }
        guard let selected = eventSelection.wrappedValue else { return 0.18 }
        return selected == id ? 1 : 0.08
    }
    private func eventWidth(_ id: String) -> CGFloat { eventSelection?.wrappedValue == id ? 2.5 : 1 }

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

    /// 같은 시각(2분 안) 인슐린 묶음: 첫 기록 순번, 시각, 개수
    private var insulinGroups: [(first: Int, time: Date, count: Int)] {
        var groups: [(first: Int, time: Date, count: Int)] = []
        for (index, event) in insulinEvents.enumerated().sorted(by: { $0.element.occurredAt < $1.element.occurredAt }) {
            if let last = groups.last, abs(event.occurredAt.timeIntervalSince(last.time)) <= 120 {
                groups[groups.count - 1].count += 1
            } else {
                groups.append((index, event.occurredAt, 1))
            }
        }
        return groups
    }

    /// 인슐린 표시를 놓을 높이: 세로축 바닥 바로 위
    private var insulinBadgeY: Double {
        Double(yDomain.lowerBound) + Double(yDomain.upperBound - yDomain.lowerBound) * 0.045
    }

    private var selectedPoint: GlucosePoint? {
        guard let time = selection?.wrappedValue else { return nil }
        return GlucoseCurve(points: points).nearestObservedPoint(to: time)
    }

    var body: some View {
        let chart = Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("시각", point.time),
                    y: .value("혈당", point.value),
                    series: .value("구간", point.segment)
                )
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Color.textPrimary)
            }

            // 앞뒤가 다 끊긴 단독 값은 선이 안 그려지므로 점으로 표시한다.
            ForEach(isolatedPoints) { point in
                PointMark(x: .value("시각", point.time), y: .value("혈당", point.value))
                    .symbolSize(16)
                    .foregroundStyle(Color.textPrimary)
            }

            ForEach(Array(marks.enumerated()), id: \.offset) { index, mark in
                RuleMark(x: .value("기록", mark.occurredAt))
                    .lineStyle(StrokeStyle(lineWidth: eventWidth("intake-\(index)"), dash: [3, 3]))
                    .foregroundStyle(mark.context.tint.opacity(eventOpacity("intake-\(index)")))
                    .annotation(position: .top, spacing: 2) {
                        if eventSelection == nil && (!showsPhotos || mark.photoId == nil) {
                            Image(systemName: mark.context.systemImage)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(mark.context.tint)
                        }
                    }
            }

            // 사진은 그 시각 곡선 값에 붙인다. 그래프 안의 점에 달려 있어서 옆으로 넘기거나 확대해도 곡선과 함께 움직인다
            if showsPhotos && eventSelection == nil {
                ForEach(photoGroups) { group in
                    PointMark(x: .value("사진", group.time),
                              y: .value("혈당", group.anchorValue ?? Double(yDomain.lowerBound + 10)))
                        .symbolSize(36)
                        .foregroundStyle(group.members[0].mark.context.tint)
                        .annotation(position: .top, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            ChartPhotoBadge(group: group, size: 34)
                                .opacity(selection?.wrappedValue == nil ? 1 : 0.3)
                        }
                }
            }

            ForEach(Array(insulinEvents.enumerated()), id: \.offset) { index, event in
                RuleMark(x: .value("인슐린", event.occurredAt))
                    .lineStyle(StrokeStyle(lineWidth: eventWidth("insulin-\(index)"), dash: [1, 2]))
                    .foregroundStyle(Color.insulin.opacity(eventOpacity("insulin-\(index)")))
            }
            // 곡선 아래 바닥에 주사기 표시: 언제 맞았는지 바로 보인다(그래프 안에 있어 넘기거나 확대해도 따라온다).
            // 같은 시각에 두 가지를 맞았으면 하나로 묶고 개수를 붙인다
            ForEach(insulinGroups, id: \.first) { group in
                PointMark(x: .value("인슐린", group.time), y: .value("혈당", insulinBadgeY))
                    .symbol { InsulinChartBadge(count: group.count) }
                    .opacity(eventOpacity("insulin-\(group.first)"))
                    .accessibilityLabel("인슐린 \(group.count)가지 \(ReportDay.timeString(from: group.time))")
            }

            if let time = selection?.wrappedValue, selectedPoint == nil {
                RuleMark(x: .value("선택", time))
                    .foregroundStyle(Color.textSecondary)
                    .annotation(position: .top) { Text("값 없음").font(.caption1) }
            }
            if let point = selectedPoint {
                RuleMark(x: .value("선택", point.time))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(Color.brand)
                PointMark(x: .value("선택", point.time), y: .value("혈당", point.value))
                    .symbolSize(90)
                    .foregroundStyle(Color.textPrimary)
                    .annotation(position: .top, spacing: 6,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        if showsSelectionCallout {
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
        }
        .chartXScale(domain: dayRange)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: displayDuration <= 6 * 3600 ? 1 : 3)) { value in
                AxisGridLine().foregroundStyle(Color.line)
                AxisValueLabel(centered: false, anchor: .top) {
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
        .chartOverlay { proxy in
            if let eventSelection {
                GeometryReader { geometry in
                    if let container = proxy.plotContainerFrame {
                        let frame = geometry[container]
                        ChartEventMarkers(events: events, points: points, range: visibleRange,
                                          size: frame.size, proxy: proxy, selectedID: eventSelection,
                                          onSelect: { onSelectEventCluster?($0) })
                            .offset(x: frame.minX, y: frame.minY)
                    }
                }
            }
        }

        Group {
            if let selection, let scrollPosition, visibleDuration != nil || visibleHours != nil {
                if let eventSelection {
                    chart
                        .chartScrollableAxes(.horizontal)
                        .chartXVisibleDomain(length: displayDuration)
                        .chartScrollPosition(x: scrollPosition)
                        .chartXSelection(value: selection)
                        .chartGesture { proxy in
                            SpatialTapGesture().onEnded { value in
                                eventSelection.wrappedValue = nil
                                proxy.selectXValue(at: value.location.x)
                            }
                        }
                } else if selectsByTap {
                    chart
                        .chartScrollableAxes(.horizontal)
                        .chartXVisibleDomain(length: displayDuration)
                        .chartScrollPosition(x: scrollPosition)
                        .chartXSelection(value: selection)
                        .chartGesture { proxy in
                            SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) }
                        }
                } else {
                    chart
                        .chartScrollableAxes(.horizontal)
                        .chartXVisibleDomain(length: displayDuration)
                        .chartScrollPosition(x: scrollPosition)
                        .chartXSelection(value: selection)
                }
            } else if let selection, selectsByTap {
                chart
                    .chartXSelection(value: selection)
                    .chartGesture { proxy in
                        SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) }
                    }
            } else if let selection {
                chart.chartXSelection(value: selection)
            } else {
                chart
            }
        }
        .accessibilityElement(children: showsPhotos || eventSelection != nil ? .contain : .ignore)
        .accessibilityLabel("하루 혈당 곡선")
        .accessibilityValue(accessibilitySummary)

        if showsPhotos, !photoGroups.isEmpty {
            ChartPhotoTimeline(groups: photoGroups) { onSelectPhoto?($0) }
        }
    }

    private var photoGroups: [ChartPhotoGroup] {
        ChartPhotoGroup.make(marks: marks, day: day, points: points)
    }

    private var accessibilitySummary: String {
        guard let minValue = points.map(\.value).min(), let maxValue = points.map(\.value).max() else {
            return "값 없음"
        }
        return "최저 \(minValue), 최고 \(maxValue) mg/dL, 섭취 기록 \(marks.count)개, 인슐린 기록 \(insulinEvents.count)개"
    }
}

/// 그래프 바닥의 인슐린 표시(보라 동그라미 + 주사기)
struct InsulinChartBadge: View {
    /// 같은 시각에 함께 맞은 개수
    var count = 1

    var body: some View {
        Image(systemName: "syringe.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Color.insulin, in: Circle())
            .overlay(Circle().strokeBorder(Color.canvas, lineWidth: 1.5))
            .overlay(alignment: .topTrailing) {
                if count > 1 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color.onButton)
                        .frame(width: 13, height: 13)
                        .background(Color.buttonFill, in: Circle())
                        .offset(x: 6, y: -6)
                }
            }
            .accessibilityHidden(true)
    }
}
