//
//  GlucoseDayDetailView.swift
//  glucose
//
//  하루 그래프 크게 보기. 일일 리포트 맨 위와 같은 DayChartExplorer를 화면 가득 크게 보여준다.
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

    init(day: Date, points: [GlucosePoint], episodes: [DailyReport.Episode], insulinEvents: [DailyReport.InsulinMarker],
         onChanged: @escaping () async -> Void = {}) {
        self.day = day
        self.points = points
        self.episodes = episodes
        self.insulinEvents = insulinEvents
        self.onChanged = onChanged
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                DayChartExplorer(day: day, points: points, episodes: episodes, insulinEvents: insulinEvents,
                                 chartHeight: 400, onSelectPhoto: { selectedPhoto = $0 })
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
        }
    }
}
