import Foundation

@MainActor
protocol ReportRecordReading {
    func page(cursor: String?) async throws -> PageResponse<IntakeResponse>
}

@MainActor
struct LiveReportRecordReader: ReportRecordReading {
    func page(cursor: String?) async throws -> PageResponse<IntakeResponse> {
        var query = [URLQueryItem(name: "limit", value: "100")]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await APIClient.shared.send(path: "/v1/intakes", queryItems: query)
    }
}

@MainActor
struct ReportRecordResolver {
    enum Resolution: Equatable {
        case found(IntakeRecord)
        case missing
        case ambiguous
        case unavailable
    }

    private let reader: ReportRecordReading
    private let maxPages: Int
    init(reader: ReportRecordReading? = nil, maxPages: Int = 20) {
        self.reader = reader ?? LiveReportRecordReader()
        self.maxPages = maxPages
    }

    func resolve(mark: DailyReport.Episode.IntakeMark) async throws -> Resolution {
        var cursor: String?
        var seenCursors = Set<String>()
        var matches: [UUID: IntakeRecord] = [:]
        for _ in 0..<max(0, maxPages) {
            try Task.checkCancellation()
            let page = try await reader.page(cursor: cursor)
            try Task.checkCancellation()
            for item in page.items where abs(item.occurredAt.timeIntervalSince(mark.occurredAt)) < 0.001
                && item.photoId == mark.photoId && item.context == mark.context.rawValue {
                matches[item.id] = item.toRecord()
            }
            if matches.count > 1 { return .ambiguous }
            let passedTarget = page.items.contains { $0.occurredAt < mark.occurredAt.addingTimeInterval(-0.001) }
            if page.nextCursor == nil || passedTarget {
                return matches.values.first.map(Resolution.found) ?? .missing
            }
            guard let next = page.nextCursor, seenCursors.insert(next).inserted else { return .unavailable }
            cursor = next
        }
        return .unavailable
    }
}
