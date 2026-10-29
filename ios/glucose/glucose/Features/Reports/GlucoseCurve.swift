import Foundation

/// 선의 위치만 계산한다. 계산한 위치를 관측 혈당값으로 보여주거나 저장하지 않는다.
struct GlucoseCurve {
    private let points: [GlucosePoint]

    init(points: [GlucosePoint]) { self.points = points.sorted { $0.time < $1.time } }

    func anchorValue(at time: Date) -> Double? {
        if let exact = points.first(where: { abs($0.time.timeIntervalSince(time)) < 0.000_001 }) {
            return Double(exact.value)
        }
        guard let before = points.last(where: { $0.time < time }),
              let after = points.first(where: { $0.time > time }),
              before.segment == after.segment else { return nil }
        let span = after.time.timeIntervalSince(before.time)
        guard span > 0, span <= GlucosePoint.interval else { return nil }
        let fraction = time.timeIntervalSince(before.time) / span
        return Double(before.value) + Double(after.value - before.value) * fraction
    }

    func nearestObservedPoint(to time: Date) -> GlucosePoint? {
        guard anchorValue(at: time) != nil else { return nil }
        return points.min { abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time)) }
    }
}
