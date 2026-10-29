//
//  GlucoseDayDetailView.swift
//  glucose
//
//  하루 그래프 크게 보기. 시간 범위를 골라 확대하고 옆으로 넘겨 보며, 그래프를 누르면 그 시각의 값과
//  앞뒤 45분 안의 기록(음식 사진·이름, 인슐린)을 보여준다. 기록 목록을 누르면 그 시각으로 이동한다.
//  수치와 기록을 나란히 보여줄 뿐, 기록이 수치를 바꿨다고 말하지 않는다.
//

import SwiftUI

struct GlucoseDayDetailView: View {
    let day: Date
    let points: [GlucosePoint]
    let episodes: [DailyReport.Episode]
    let insulinEvents: [DailyReport.InsulinMarker]

    var onChanged: () async -> Void = {}
    @State private var selectedPhoto: ChartPhotoGroup?

    @Environment(\.dismiss) private var dismiss
    @State private var visibleHours = 24
    @State private var selection: Date?
    @State private var scrollPosition: Date

    private static let nearbyWindow: TimeInterval = 45 * 60

    init(day: Date, points: [GlucosePoint], episodes: [DailyReport.Episode], insulinEvents: [DailyReport.InsulinMarker],
         onChanged: @escaping () async -> Void = {}) {
        self.day = day
        self.points = points
        self.episodes = episodes
        self.insulinEvents = insulinEvents
        self.onChanged = onChanged
        _scrollPosition = State(initialValue: ReportDay.calendar.startOfDay(for: day))
    }

    private var marks: [DailyReport.Episode.IntakeMark] {
        episodes.flatMap(\.marks).sorted { $0.occurredAt < $1.occurredAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    zoomControl
                    if let selection {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "hand.tap.fill").font(.caption)
                            Text("선택한 시각 \(ReportDay.timeString(from: selection))")
                                .font(.caption1.weight(.semibold))
                            Spacer()
                            Button("선택 해제") { self.selection = nil }
                                .font(.caption1.weight(.semibold))
                        }
                        .foregroundStyle(Color.onBrandSoft)
                        .padding(.horizontal, Spacing.s)
                        .padding(.vertical, Spacing.xs)
                        .background(Color.brandSoft, in: Capsule())
                    }

                    GlucoseDayChart(day: day, points: points, episodes: episodes, insulinEvents: insulinEvents,
                                    height: 360, visibleHours: visibleHours, selection: $selection,
                                    scrollPosition: $scrollPosition, showsPhotos: true,
                                    onSelectPhoto: { selectedPhoto = $0 })
                        .padding(.top, Spacing.l)
                        .card(padding: Spacing.s)

                    Text(visibleHours < 24 ? "옆으로 넘겨 다른 시간을 보고, 그래프를 누르면 그 시각의 값이 보여요."
                                           : "그래프를 누르면 그 시각의 값과 앞뒤 기록이 보여요.")
                        .font(.caption1)
                        .foregroundStyle(Color.textSecondary)

                    if let selection {
                        selectedCard(selection)
                    }

                    recordsCard
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.m)
            }
            .background(Color.canvas)
            .navigationTitle(ReportDay.displayString(from: day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }.accessibilityIdentifier("closeChartDetail")
                }
            }
            .sheet(item: $selectedPhoto) { group in
                ReportPhotoGallery(group: group) {
                    selectedPhoto = nil
                    dismiss()
                    await onChanged()
                }
            }
            .onChange(of: visibleHours) { _, hours in
                // 확대하면 고른 시각(없으면 첫 기록)이 화면에 들어오게 옮긴다
                guard hours < 24 else {
                    scrollPosition = ReportDay.calendar.startOfDay(for: day)
                    return
                }
                let center = selection ?? marks.first?.occurredAt ?? scrollPosition
                move(to: center)
            }
        }
    }

    // MARK: - 확대 단계(선택된 칸을 진하게)

    private var zoomControl: some View {
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
                .accessibilityIdentifier("detailChartZoom-\(hours)")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.surfaceMuted, in: Capsule())
    }

    /// 고른 시각과 가까운(앞뒤 45분) 기록인지
    private func isNearSelection(_ time: Date) -> Bool {
        guard let selection else { return false }
        return abs(time.timeIntervalSince(selection)) <= Self.nearbyWindow
    }

    // MARK: - 고른 시각

    private func selectedCard(_ time: Date) -> some View {
        let point = nearestPoint(to: time)
        let nearbyMarks = marks.filter { abs($0.occurredAt.timeIntervalSince(time)) <= Self.nearbyWindow }
        let nearbyInsulin = insulinEvents.filter { abs($0.occurredAt.timeIntervalSince(time)) <= Self.nearbyWindow }
        return VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(ReportDay.timeString(from: point?.time ?? time))
                    .font(.headline2)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                if let point {
                    Text("\(point.value)")
                        .font(.pretendard(32, relativeTo: .title, weight: .black))
                        .foregroundStyle(Color.textPrimary)
                    Text("mg/dL").font(.caption1).foregroundStyle(Color.textSecondary)
                } else {
                    Text("이 시각은 그래프가 비어 있어요").font(.body2).foregroundStyle(Color.textSecondary)
                }
            }
            if nearbyMarks.isEmpty && nearbyInsulin.isEmpty {
                Text("앞뒤 45분 안에 남긴 기록이 없어요.")
                    .font(.body2)
                    .foregroundStyle(Color.textSecondary)
            } else {
                Text("앞뒤 45분 안의 기록")
                    .font(.sectionLabel)
                    .foregroundStyle(Color.textSecondary)
                ForEach(Array(nearbyMarks.enumerated()), id: \.offset) { _, mark in markRow(mark) }
                ForEach(Array(nearbyInsulin.enumerated()), id: \.offset) { _, event in insulinRow(event) }
            }
        }
        .card(.brand)
    }

    // MARK: - 하루 기록

    private var recordsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "이날 기록", trailing: "\(marks.count + insulinEvents.count)건")
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
                    .overlay(RoundedRectangle(cornerRadius: Radius.field)
                        .strokeBorder(isNearSelection(entry.time) ? Color.brand : Color.clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
        .card()
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
                FoodPhotoThumbnail(photoId: photoId, size: 48)
            } else {
                Image(systemName: mark.context.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(mark.context == .hypoTreatment ? Color.mintStrong : Color.onBrandSoft)
                    .frame(width: 48, height: 48)
                    .background(mark.context == .hypoTreatment ? Color.mintSoft : Color.brandSoft,
                                in: RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(ReportDay.timeString(from: mark.occurredAt)) · \(mark.context.displayName)")
                    .font(.caption1)
                    .foregroundStyle(Color.textSecondary)
                Text((mark.foods ?? []).isEmpty ? "음식 이름 없음" : (mark.foods ?? []).joined(separator: ", "))
                    .font(.body1)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                if let point = nearestPoint(to: mark.occurredAt) {
                    Text("가까운 관측 · \(ReportDay.timeString(from: point.time)) · \(point.value) mg/dL")
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
                .frame(width: 48, height: 48)
                .background(Color.insulinSoft, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(ReportDay.timeString(from: event.occurredAt)) · 인슐린")
                    .font(.caption1)
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
