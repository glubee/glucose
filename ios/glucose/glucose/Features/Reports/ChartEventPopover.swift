import SwiftUI

struct ChartEventPopover: View {
    let events: [ChartEvent]
    @Binding var selectedID: String?
    let points: [GlucosePoint]
    let onClose: () -> Void
    @State private var route: Route?

    private enum Route: Identifiable {
        case record(ChartEvent)
        case photo(ChartEvent)
        var id: String {
            switch self { case .record(let event): "record-\(event.id)"; case .photo(let event): "photo-\(event.id)" }
        }
    }
    private var selected: ChartEvent? { events.first { $0.id == selectedID } ?? events.first }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text("이 시각의 기록").font(.headline2)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("기록 팝업 닫기")
                    .accessibilityIdentifier("closeChartEventPopup")
            }
            if events.count > 1 {
                Text("기록 \(events.count)건 · 항목을 누르면 해당 시각이 강조돼요")
                    .font(.caption1).foregroundStyle(Color.textSecondary)
            }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(events) { event in
                        Button { selectedID = event.id } label: {
                            HStack(alignment: .top, spacing: Spacing.xs) {
                                Image(systemName: event.symbolName).frame(width: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(ReportDay.timeString(from: event.time)) · \(event.title)").font(.body2.weight(.semibold))
                                    Text(event.summary).font(.body2).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                if selectedID == event.id { Image(systemName: "checkmark") }
                            }
                            .foregroundStyle(event.color)
                            .padding(8)
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .background(selectedID == event.id ? Color.brandSoft : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("popupEvent-\(event.id)")
                        .accessibilityAddTraits(selectedID == event.id ? .isSelected : [])
                    }
                    if let event = selected {
                        if GlucoseCurve(points: points).anchorValue(at: event.time) == nil {
                            Text("이 시각의 혈당 데이터는 없어요.").font(.caption1).foregroundStyle(Color.textSecondary)
                        }
                        if let photoId = event.photoId {
                            HStack {
                                FoodPhotoThumbnail(photoId: photoId, size: 48)
                                Button("사진 크게 보기") { route = .photo(event) }
                                    .font(.body2.weight(.semibold)).frame(minHeight: 44)
                            }
                        }
                        Button("기록 상세") { route = .record(event) }
                            .buttonStyle(.glubeeSecondary)
                            .accessibilityIdentifier("chartEventRecordDetail")
                    }
                }
            }
            .frame(height: 200)
            .accessibilityIdentifier("chartEventPopupContents")
        }
        .padding(Spacing.s)
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.canvas)
        .sheet(item: $route) { route in
            switch route {
            case .record(let event):
                NavigationStack {
                    ChartEventRecordDestination(event: event) { self.route = nil; onClose() }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("닫기") { self.route = nil }.accessibilityIdentifier("closeChartRecord")
                            }
                        }
                }
            case .photo(let event):
                if case .intake(let mark) = event.kind,
                   let group = ChartPhotoGroup.make(marks: [mark], day: mark.occurredAt, points: points).first {
                    ReportPhotoGallery(group: group) { self.route = nil; onClose() }
                }
            }
        }
    }
}
