import SwiftUI

/// 현재 화면에서 확대·이동하고 기록을 확인한다. 한 손가락 세로 드래그는 부모 스크롤에 맡긴다.
struct InteractiveGlucoseChart: View {
    let day: Date
    let points: [GlucosePoint]
    let episodes: [DailyReport.Episode]
    let insulinEvents: [DailyReport.InsulinMarker]
    var height: CGFloat = 260
    var showsPhotos = false
    var onSelectPhoto: ((ChartPhotoGroup) -> Void)? = nil

    @State private var viewport: ChartViewport
    @State private var pinchStart: ChartViewport?
    @State private var selectedEventID: String?
    @State private var selectedTime: Date?
    @State private var focusedEventTime: Date?
    @State private var hasZoomed = false
    @State private var openCluster: ChartEventCluster?
    @State private var markerRects: [String: CGRect] = [:]

    init(day: Date, points: [GlucosePoint], episodes: [DailyReport.Episode],
         insulinEvents: [DailyReport.InsulinMarker], height: CGFloat = 260, showsPhotos: Bool = false,
         onSelectPhoto: ((ChartPhotoGroup) -> Void)? = nil) {
        self.day = day
        self.points = points
        self.episodes = episodes
        self.insulinEvents = insulinEvents
        self.height = height
        self.showsPhotos = showsPhotos
        self.onSelectPhoto = onSelectPhoto
        _viewport = State(initialValue: ChartViewport(day: day))
    }

    private var events: [ChartEvent] { ChartEvent.make(day: day, episodes: episodes, insulinEvents: insulinEvents) }
    private var scrollPosition: Binding<Date> {
        Binding(get: { viewport.start }, set: { value in
            guard abs(value.timeIntervalSince(viewport.start)) > 0.01 else { return }
            viewport.scroll(to: value)
            focusedEventTime = nil
            hasZoomed = true
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: 3) {
                ForEach([24, 12, 6, 3], id: \.self) { hours in
                    let active = abs(viewport.duration - Double(hours) * 3600) < 1
                    Button(hours == 24 ? "하루" : "\(hours)시간") {
                        let center = events.first(where: { $0.id == selectedEventID })?.time
                            ?? selectedTime ?? focusedEventTime ?? (hasZoomed ? nil : events.first?.time)
                        selectedEventID = nil
                        selectedTime = nil
                        viewport.setHours(hours, around: center)
                        hasZoomed = true
                    }
                    .font(.caption1.weight(active ? .bold : .medium))
                    .foregroundStyle(active ? Color.onButton : Color.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(active ? Color.buttonFill : Color.surfaceMuted, in: Capsule())
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chartZoom-\(hours)")
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
            HStack {
                Button { move(by: -viewport.duration / 2) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .accessibilityLabel("이전 시간 보기")
                .disabled(viewport.start <= viewport.day)
                Spacer(minLength: 0)
                Text(rangeText).font(.caption1).monospacedDigit()
                    .accessibilityIdentifier("chartVisibleRange")
                Spacer(minLength: 0)
                Button { move(by: viewport.duration / 2) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .accessibilityLabel("다음 시간 보기")
                .disabled(viewport.range.upperBound >= viewport.day.addingTimeInterval(86_400))
            }
            .foregroundStyle(Color.textSecondary)
            .buttonStyle(.plain)

            GlucoseDayChart(day: day, points: points, episodes: episodes, insulinEvents: insulinEvents,
                            height: height, visibleDuration: viewport.duration, selection: $selectedTime,
                            scrollPosition: scrollPosition, showsPhotos: showsPhotos,
                            onSelectPhoto: onSelectPhoto, eventSelection: $selectedEventID,
                            onSelectEventCluster: selectCluster)
                .simultaneousGesture(MagnifyGesture().onChanged { value in
                    if pinchStart == nil { pinchStart = viewport; focusedEventTime = nil; hasZoomed = true }
                    var next = pinchStart ?? viewport
                    next.zoom(by: value.magnification, anchor: value.startAnchor.x)
                    viewport = next
                }.onEnded { _ in pinchStart = nil })
                .accessibilityIdentifier("interactiveChartPlot")

            Text("아이콘을 누르면 기록을 볼 수 있어요. 두 손가락으로 확대하고 옆으로 넘겨 보세요.")
                .font(.caption1).foregroundStyle(Color.textSecondary)
            Text("선이 비어 있는 구간은 혈당 데이터가 없어요.")
                .font(.caption1).foregroundStyle(Color.textSecondary)
            if let event = events.first(where: { $0.id == selectedEventID }) {
                Text("선택: \(ReportDay.timeString(from: event.time)) · \(event.title)")
                    .font(.caption1.weight(.semibold)).foregroundStyle(event.color)
                    .accessibilityIdentifier("selectedChartEvent")
            }
        }
        .backgroundPreferenceValue(ChartMarkerAnchorKey.self) { anchors in
            GeometryReader { geometry in
                Color.clear.preference(key: ChartMarkerRectKey.self, value: anchors.mapValues { geometry[$0] })
            }
        }
        .onPreferenceChange(ChartMarkerRectKey.self) { markerRects = $0 }
        .popover(isPresented: popupPresentation,
                 attachmentAnchor: .rect(.rect(popupAnchor))) {
            if let openCluster {
                ChartEventPopover(events: openCluster.events, selectedID: $selectedEventID,
                                  points: points, onClose: closePopup)
                    .presentationCompactAdaptation(.popover)
            }
        }
        .onChange(of: viewport) { _, _ in selectedEventID = nil; selectedTime = nil }
        .onChange(of: selectedEventID) { _, id in
            if let event = events.first(where: { $0.id == id }) { focusedEventTime = event.time }
            if id == nil { openCluster = nil }
        }
        .onChange(of: day) { _, newDay in
            viewport = ChartViewport(day: newDay); selectedEventID = nil; focusedEventTime = nil; hasZoomed = false
        }
        .onChange(of: events.map(\.fingerprint)) { _, _ in selectedEventID = nil; focusedEventTime = nil }
        .onChange(of: RecordChanges.shared.revision) { _, _ in selectedEventID = nil; focusedEventTime = nil }
    }

    private var popupPresentation: Binding<Bool> {
        Binding(get: { openCluster != nil && selectedEventID != nil }, set: { if !$0 { closePopup() } })
    }
    private var popupAnchor: CGRect {
        openCluster.flatMap { markerRects[$0.id] } ?? CGRect(x: 0, y: 0, width: 44, height: 44)
    }
    private func selectCluster(_ cluster: ChartEventCluster) {
        if openCluster?.id == cluster.id { closePopup() }
        else { openCluster = cluster; selectedEventID = cluster.events.first?.id }
    }
    private func closePopup() { openCluster = nil; selectedEventID = nil }

    private func move(by seconds: TimeInterval) {
        focusedEventTime = nil
        hasZoomed = true
        viewport.move(by: seconds)
    }

    private var rangeText: String {
        let end = viewport.range.upperBound
        let endText = end == viewport.day.addingTimeInterval(86_400) ? "24:00" : ReportDay.timeString(from: end)
        return "\(ReportDay.timeString(from: viewport.start)) – \(endText)"
    }
}
