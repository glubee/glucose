import SwiftUI

/// 화면의 기록 표시 한 개. 동일 시각/사진이어도 저장 기록별로 보존한다.
struct ChartEvent: Identifiable {
    enum Kind {
        case intake(DailyReport.Episode.IntakeMark)
        case insulin(DailyReport.InsulinMarker)
    }
    let id: String
    let kind: Kind

    var time: Date {
        switch kind { case .intake(let mark): mark.occurredAt; case .insulin(let event): event.occurredAt }
    }
    var title: String {
        switch kind { case .intake(let mark): mark.context.displayName; case .insulin: "인슐린" }
    }
    var symbolName: String {
        switch kind { case .intake(let mark): mark.context.systemImage; case .insulin: "syringe" }
    }
    var color: Color {
        switch kind {
        case .intake(let mark): mark.context == .hypoTreatment ? .mintStrong : .onBrandSoft
        case .insulin: .insulin
        }
    }
    var summary: String {
        switch kind {
        case .intake(let mark): (mark.foods ?? []).isEmpty ? "음식 이름 없음" : (mark.foods ?? []).joined(separator: ", ")
        case .insulin(let event): "\(event.units.formatted())단위 · \(event.kind)"
        }
    }
    var photoId: UUID? {
        if case .intake(let mark) = kind { return mark.photoId }
        return nil
    }
    var fingerprint: String { "\(id)|\(time.timeIntervalSince1970)|\(title)|\(summary)|\(photoId?.uuidString ?? "")" }

    static func make(day: Date, episodes: [DailyReport.Episode], insulinEvents: [DailyReport.InsulinMarker]) -> [ChartEvent] {
        let intakes = episodes.flatMap(\.marks).enumerated().map { ChartEvent(id: "intake-\($0.offset)", kind: .intake($0.element)) }
        let insulin = insulinEvents.enumerated().map { ChartEvent(id: "insulin-\($0.offset)", kind: .insulin($0.element)) }
        return (intakes + insulin).filter { ReportDay.calendar.isDate($0.time, inSameDayAs: day) }
            .sorted { $0.time == $1.time ? $0.id < $1.id : $0.time < $1.time }
    }
}

struct ChartEventCluster: Identifiable {
    let events: [ChartEvent]
    let x: CGFloat
    var id: String { events[0].id }
    var time: Date { events[0].time }
    var label: String {
        events.count == 1 ? "\(ReportDay.timeString(from: time)) \(events[0].title)" : "기록 \(events.count)건"
    }

    /// 화면의 터치 영역(60pt)이 닿을 때만 묶는다. 확대하면 같은 자료도 분리된다.
    static func make(events: [ChartEvent], range: ClosedRange<Date>, width: CGFloat) -> [ChartEventCluster] {
        let duration = range.upperBound.timeIntervalSince(range.lowerBound)
        guard width.isFinite, width > 0, duration.isFinite, duration > 0 else { return [] }
        let visible = events.filter { range.contains($0.time) }.sorted { $0.time == $1.time ? $0.id < $1.id : $0.time < $1.time }
        if width < 60 { return visible.isEmpty ? [] : [.init(events: visible, x: width / 2)] }
        var groups: [ChartEventCluster] = []
        for event in visible {
            let x = min(max(CGFloat(event.time.timeIntervalSince(range.lowerBound) / duration) * width, 30), width - 30)
            if let last = groups.last, x - last.x < 60 {
                groups[groups.count - 1] = .init(events: last.events + [event], x: last.x)
            } else { groups.append(.init(events: [event], x: x)) }
        }
        return groups
    }
}
