import Foundation

struct ChartViewport: Equatable {
    let day: Date
    private(set) var start: Date
    private(set) var duration: TimeInterval = 24 * 3600
    private var end: Date { day.addingTimeInterval(24 * 3600) }
    var range: ClosedRange<Date> { start...start.addingTimeInterval(duration) }

    init(day: Date) {
        self.day = ReportDay.calendar.startOfDay(for: day)
        start = ReportDay.calendar.startOfDay(for: day)
    }

    mutating func setHours(_ hours: Int, around center: Date? = nil) {
        let target = center ?? start.addingTimeInterval(duration / 2)
        duration = min(max(Double(hours) * 3600, 3 * 3600), 24 * 3600)
        scroll(to: target.addingTimeInterval(-duration / 2))
    }
    mutating func scroll(to date: Date) {
        guard date.timeIntervalSince1970.isFinite else { return }
        start = min(max(date, day), end.addingTimeInterval(-duration))
    }
    mutating func move(by seconds: TimeInterval) {
        guard seconds.isFinite else { return }
        scroll(to: start.addingTimeInterval(seconds))
    }
    mutating func zoom(by magnification: Double, anchor: Double) {
        guard magnification.isFinite, magnification > 0, anchor.isFinite else { return }
        let fraction = min(max(anchor, 0), 1)
        let anchorTime = start.addingTimeInterval(duration * fraction)
        duration = min(max(duration / magnification, 3 * 3600), 24 * 3600)
        scroll(to: anchorTime.addingTimeInterval(-duration * fraction))
    }
}
