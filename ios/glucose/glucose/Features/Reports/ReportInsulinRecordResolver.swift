import Foundation

@MainActor
struct ReportInsulinRecordResolver {
    enum Resolution: Equatable {
        case found(RecordItem)
        case missing
        case ambiguous
        case unavailable
    }
    private let reader: RecordRepository
    init(reader: RecordRepository? = nil) { self.reader = reader ?? LiveRecordRepository() }

    func resolve(_ marker: DailyReport.InsulinMarker) async throws -> Resolution {
        var cursor: String?
        var seen = Set<String>()
        var matches: [UUID: RecordItem] = [:]
        for _ in 0..<20 {
            try Task.checkCancellation()
            let page = try await reader.fetchInsulinPage(cursor: cursor, limit: 100)
            try Task.checkCancellation()
            for item in page.items {
                if case .insulin(let record) = item,
                   abs(record.occurredAt.timeIntervalSince(marker.occurredAt)) < 0.001,
                   record.units == marker.units, record.kind == marker.kind { matches[item.id] = item }
            }
            if matches.count > 1 { return .ambiguous }
            if page.nextCursor == nil || page.items.contains(where: { $0.occurredAt < marker.occurredAt.addingTimeInterval(-0.001) }) {
                return matches.values.first.map(Resolution.found) ?? .missing
            }
            guard let next = page.nextCursor, seen.insert(next).inserted else { return .unavailable }
            cursor = next
        }
        return .unavailable
    }
}
