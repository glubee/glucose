import Charts
import SwiftUI

/// 팝업은 Chart의 스크롤 컨테이너 바깥에서 표시한다. 버튼의 실제 위치만 부모에게 전달한다.
struct ChartMarkerAnchorKey: PreferenceKey {
    nonisolated static var defaultValue: [String: Anchor<CGRect>] { [:] }
    nonisolated static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
struct ChartMarkerRectKey: PreferenceKey {
    nonisolated static var defaultValue: [String: CGRect] { [:] }
    nonisolated static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct ChartEventMarkers: View {
    let events: [ChartEvent]
    let points: [GlucosePoint]
    let range: ClosedRange<Date>
    let size: CGSize
    let proxy: ChartProxy
    @Binding var selectedID: String?
    let onSelect: (ChartEventCluster) -> Void

    var body: some View {
        let clusters = ChartEventCluster.make(events: events, range: range, width: size.width)
        ZStack(alignment: .topLeading) {
            ForEach(clusters) { cluster in
                let point = anchor(for: cluster)
                let selected = cluster.events.contains { $0.id == selectedID }
                Button { onSelect(cluster) } label: {
                    VStack(spacing: 1) {
                        Image(systemName: cluster.events.count == 1 ? cluster.events[0].symbolName : "square.stack.3d.up")
                            .font(.system(size: 16, weight: .semibold))
                        if cluster.events.count > 1 { Text("기록 \(cluster.events.count)건").font(.caption2.weight(.bold)) }
                    }
                    .foregroundStyle(selected ? Color.onButton : cluster.events[0].color)
                    .frame(width: 58, height: 44)
                    .background(selected ? Color.buttonFill : Color.canvas, in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(selected ? Color.buttonFill : Color.line))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(cluster.label)
                .accessibilityIdentifier("chartEvent-\(cluster.id)")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .anchorPreference(key: ChartMarkerAnchorKey.self, value: .bounds) { [cluster.id: $0] }
                .position(point)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func anchor(for cluster: ChartEventCluster) -> CGPoint {
        let value = GlucoseCurve(points: points).anchorValue(at: cluster.time)
        let curveY = value.flatMap { proxy.position(forY: $0) } ?? (size.height - 12)
        return CGPoint(x: cluster.x, y: min(max(curveY - 28, 24), max(24, size.height - 24)))
    }
}
