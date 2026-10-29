//
//  DayChartExplorer.swift
//  glucose
//
//  하루 그래프 살펴보기: 일일 리포트 맨 위와 "크게 보기"가 같이 쓴다.
//  확대 단계(하루/12/6/3시간) + 옆으로 넘기기, 그래프를 누르면 그 시각의 값을 그래프 밖 띠에 보여준다(사진에 가리지 않게).
//  사진은 곡선 위 그 시각에 붙어 함께 움직이고, 아래 "이날 기록"은 시각순 기록(상황별 색)을 보여준다.
//  수치와 기록을 나란히 보여줄 뿐, 기록이 수치를 바꿨다고 말하지 않는다.
//

import SwiftUI

struct DayChartExplorer: View {
    let day: Date
    let points: [GlucosePoint]
    let episodes: [DailyReport.Episode]
    let insulinEvents: [DailyReport.InsulinMarker]
    var chartHeight: CGFloat = 300
    var onSelectPhoto: ((ChartPhotoGroup) -> Void)? = nil

    @State private var visibleHours = 24
    @State private var selection: Date?
    @State private var scrollPosition: Date

    private static let nearbyWindow: TimeInterval = 45 * 60

    init(day: Date, points: [GlucosePoint], episodes: [DailyReport.Episode], insulinEvents: [DailyReport.InsulinMarker],
         chartHeight: CGFloat = 300, onSelectPhoto: ((ChartPhotoGroup) -> Void)? = nil) {
        self.day = day
        self.points = points
        self.episodes = episodes
        self.insulinEvents = insulinEvents
        self.chartHeight = chartHeight
        self.onSelectPhoto = onSelectPhoto
        _scrollPosition = State(initialValue: ReportDay.calendar.startOfDay(for: day))
    }

    private var marks: [DailyReport.Episode.IntakeMark] {
        episodes.flatMap(\.marks).sorted { $0.occurredAt < $1.occurredAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            zoomControl
            selectionStrip
            GlucoseDayChart(day: day, points: points, episodes: episodes, insulinEvents: insulinEvents,
                            height: chartHeight, visibleHours: visibleHours, selection: $selection,
                            scrollPosition: $scrollPosition, showsPhotos: true,
                            onSelectPhoto: onSelectPhoto, showsSelectionCallout: false, selectsByTap: true)
                .padding(.top, Spacing.m)
                .accessibilityIdentifier("interactiveChartPlot")
            legend
            if let selection {
                nearbyRecords(selection)
            }
            recordsList
        }
        .onChange(of: visibleHours) { _, hours in
            guard hours < 24 else {
                scrollPosition = ReportDay.calendar.startOfDay(for: day)
                return
            }
            move(to: selection ?? marks.first?.occurredAt ?? scrollPosition)
        }
        .onChange(of: day) { _, newDay in
            selection = nil
            visibleHours = 24
            scrollPosition = ReportDay.calendar.startOfDay(for: newDay)
        }
    }

    // MARK: - 확대 단계

    private var zoomControl: some View {
        VStack(spacing: Spacing.xxs) {
            HStack(spacing: 4) {
                ForEach([(24, "하루"), (12, "12시간"), (6, "6시간"), (3, "3시간")], id: \.0) { hours, title in
                    let isOn = visibleHours == hours
                    Button {
                        withAnimation(.snappy) { visibleHours = hours }
                    } label: {
                        Text(title)
                            .font(.body2.weight(isOn ? .bold : .medium))
                            .foregroundStyle(isOn ? Color.onButton : Color.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(isOn ? Color.buttonFill : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chartZoom-\(hours)")
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(4)
            .background(Color.surfaceMuted, in: Capsule())
            if visibleHours < 24 {
                Text("\(ReportDay.timeString(from: visibleStart)) – \(ReportDay.timeString(from: visibleStart.addingTimeInterval(TimeInterval(visibleHours * 3600)))) · 옆으로 넘겨 보세요")
                    .font(.caption1.monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityIdentifier("chartVisibleRange")
            }
        }
    }

    private var visibleStart: Date { visibleHours < 24 ? scrollPosition : ReportDay.calendar.startOfDay(for: day) }

    // MARK: - 고른 시각(그래프 밖 띠)

    private var selectionStrip: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            if let selection {
                let point = nearestPoint(to: selection)
                Text(ReportDay.timeString(from: point?.time ?? selection))
                    .font(.headline2.monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
                if let point {
                    Text("\(point.value)")
                        .font(.pretendard(28, relativeTo: .title2, weight: .black))
                        .foregroundStyle(Color.textPrimary)
                    Text("mg/dL").font(.caption1).foregroundStyle(Color.textSecondary)
                } else {
                    Text("이 시각은 그래프가 비어 있어요").font(.body2).foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Button("선택 해제") { self.selection = nil }
                    .font(.caption1.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(minHeight: 32)
            } else {
                Image(systemName: "hand.tap").font(.caption).foregroundStyle(Color.textSecondary)
                Text("그래프를 누르면 그 시각의 혈당이 여기에 보여요")
                    .font(.caption1)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
            }
        }
        .padding(.horizontal, Spacing.s)
        .frame(minHeight: 48)
        .background(selection == nil ? Color.surfaceMuted : Color.brandSoft, in: RoundedRectangle(cornerRadius: Radius.field))
        .animation(.snappy, value: selection)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chartSelectionStrip")
    }

    // MARK: - 범례(상황별 색)

    private var legend: some View {
        let contexts = IntakeContext.allCases.filter { context in marks.contains { $0.context == context } }
        return FlowLegend(items: contexts.map { ($0.chipName, $0.tint) } + (insulinEvents.isEmpty ? [] : [("인슐린", Color.insulin)]))
    }

    // MARK: - 고른 시각 앞뒤 기록

    private func nearbyRecords(_ time: Date) -> some View {
        let nearbyMarks = marks.filter { abs($0.occurredAt.timeIntervalSince(time)) <= Self.nearbyWindow }
        let nearbyInsulin = insulinEvents.filter { abs($0.occurredAt.timeIntervalSince(time)) <= Self.nearbyWindow }
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("앞뒤 45분 안의 기록")
                .font(.sectionLabel)
                .foregroundStyle(Color.textSecondary)
            if nearbyMarks.isEmpty && nearbyInsulin.isEmpty {
                Text("남긴 기록이 없어요.").font(.body2).foregroundStyle(Color.textSecondary)
            }
            ForEach(Array(nearbyMarks.enumerated()), id: \.offset) { _, mark in markRow(mark) }
            ForEach(Array(nearbyInsulin.enumerated()), id: \.offset) { _, event in insulinRow(event) }
        }
        .padding(Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.brandSofter, in: RoundedRectangle(cornerRadius: Radius.field))
    }

    // MARK: - 이날 기록(시각순)

    private var recordsList: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("이날 기록 · 누르면 그 시각으로 가요")
                .font(.sectionLabel)
                .foregroundStyle(Color.textSecondary)
                .padding(.top, Spacing.xs)
            if marks.isEmpty && insulinEvents.isEmpty {
                Text("이 날 남긴 음식·인슐린 기록이 없어요.")
                    .font(.body2)
                    .foregroundStyle(Color.textSecondary)
            }
            ForEach(Array(timeline.enumerated()), id: \.offset) { _, entry in
                Button {
                    selection = entry.time
                    move(to: entry.time)
                } label: {
                    Group {
                        switch entry.kind {
                        case .intake(let mark): markRow(mark)
                        case .insulin(let event): insulinRow(event)
                        }
                    }
                    .padding(Spacing.xs)
                    .background(isNearSelection(entry.time) ? Color.brandSoft : Color.clear,
                                in: RoundedRectangle(cornerRadius: Radius.field))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private enum EntryKind {
        case intake(DailyReport.Episode.IntakeMark)
        case insulin(DailyReport.InsulinMarker)
    }

    private var timeline: [(time: Date, kind: EntryKind)] {
        (marks.map { ($0.occurredAt, EntryKind.intake($0)) } + insulinEvents.map { ($0.occurredAt, EntryKind.insulin($0)) })
            .sorted { $0.0 < $1.0 }
    }

    private func markRow(_ mark: DailyReport.Episode.IntakeMark) -> some View {
        HStack(spacing: Spacing.s) {
            if let photoId = mark.photoId {
                FoodPhotoThumbnail(photoId: photoId, size: 44)
                    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(mark.context.tint, lineWidth: 2))
            } else {
                Image(systemName: mark.context.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(mark.context.tint)
                    .frame(width: 44, height: 44)
                    .background(mark.context.softFill, in: RoundedRectangle(cornerRadius: 11))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xxs) {
                    Text(ReportDay.timeString(from: mark.occurredAt)).font(.caption1.weight(.bold).monospacedDigit())
                    Text(mark.context.chipName)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(mark.context.tint)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(mark.context.softFill, in: Capsule())
                }
                .foregroundStyle(Color.textSecondary)
                Text((mark.foods ?? []).isEmpty ? "음식 이름 없음" : (mark.foods ?? []).joined(separator: ", "))
                    .font(.body1)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                if let point = nearestPoint(to: mark.occurredAt) {
                    Text("그때 그래프 \(point.value) mg/dL")
                        .font(.caption1)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func insulinRow(_ event: DailyReport.InsulinMarker) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "syringe")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.insulin)
                .frame(width: 44, height: 44)
                .background(Color.insulinSoft, in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xxs) {
                    Text(ReportDay.timeString(from: event.occurredAt)).font(.caption1.weight(.bold).monospacedDigit())
                    Text("인슐린")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.insulin)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.insulinSoft, in: Capsule())
                }
                .foregroundStyle(Color.textSecondary)
                Text("\(event.units.formatted(.number.precision(.fractionLength(0...1))))단위 · \(event.kind)")
                    .font(.body1)
                    .foregroundStyle(Color.textPrimary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - 도움 함수

    private func isNearSelection(_ time: Date) -> Bool {
        guard let selection else { return false }
        return abs(time.timeIntervalSince(selection)) <= Self.nearbyWindow
    }

    private func nearestPoint(to time: Date) -> GlucosePoint? {
        GlucoseCurve(points: points).nearestObservedPoint(to: time)
    }

    /// 고른 시각이 화면 가운데쯤 오게 확대 구간을 옮긴다(하루 밖으로는 안 나간다)
    private func move(to time: Date) {
        guard visibleHours < 24 else { return }
        let start = ReportDay.calendar.startOfDay(for: day)
        let span = TimeInterval(visibleHours * 3600)
        let latest = start.addingTimeInterval(24 * 3600 - span)
        let target = time.addingTimeInterval(-span / 2)
        withAnimation { scrollPosition = min(max(target, start), latest) }
    }
}

/// 색 점 + 이름 범례(줄이 넘치면 다음 줄로)
struct FlowLegend: View {
    let items: [(String, Color)]

    var body: some View {
        HStack(spacing: Spacing.s) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 4) {
                    Circle().fill(item.1).frame(width: 9, height: 9)
                    Text(item.0).font(.caption1).foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

extension IntakeContext {
    /// 칩·범례에 쓰는 짧은 이름
    var chipName: String {
        switch self {
        case .meal: "식사"
        case .snack: "간식"
        case .hypoTreatment: "저혈당 대응"
        case .alcohol: "술"
        }
    }
}
