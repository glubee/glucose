import Foundation

/// 저장 기록은 서버 원본, 사진은 기기 대기 목록을 사용한다. 분석 에피소드를 기록으로 세지 않는다.
@MainActor
@Observable
final class TodayTimelineViewModel {
    private let records: RecordsViewModel
    private var day: Date?
    private var saved: [RecordItem] = []
    private var generation = UUID()
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(repository: RecordRepository = LiveRecordRepository()) {
        records = RecordsViewModel(repository: repository)
    }

    func load(day: Date) async {
        let start = ReportDay.calendar.startOfDay(for: day)
        let end = ReportDay.calendar.date(byAdding: .day, value: 1, to: start)!
        let active = UUID()
        generation = active
        if self.day != start { saved = [] }
        self.day = start
        isLoading = true
        errorMessage = nil
        defer { if active == generation { isLoading = false } }
        await records.load(filter: .all)
        while active == generation, !Task.isCancelled, records.hasMore,
              records.items.last.map({ $0.occurredAt >= start }) ?? true {
            if case .error = records.state { break }
            await records.loadNextPage()
        }
        guard active == generation, !Task.isCancelled else { return }
        if case .error(let message) = records.state { errorMessage = message }
        // 실패 시 직전 표시를 유지하며 오류를 함께 표시한다. 날짜가 바뀌면 이전 날은 남기지 않는다.
        if !records.items.isEmpty || errorMessage == nil {
            saved = records.items.filter { $0.occurredAt >= start && $0.occurredAt < end }
        }
    }

    func entries(photos: [PendingPhoto]) -> [TimelineEntry] {
        guard let day, let end = ReportDay.calendar.date(byAdding: .day, value: 1, to: day) else { return [] }
        let confirmedPhotos = Set(saved.compactMap { item -> UUID? in
            if case .intake(let record) = item { return record.photoId }
            return nil
        })
        var rows = saved.map(TimelineEntry.record)
        rows += photos.filter {
            $0.capturedAt >= day && $0.capturedAt < end && !$0.hasConfirmedRecord
            && ($0.photoId.map { !confirmedPhotos.contains($0) } ?? true)
        }.map(TimelineEntry.pending)
        return rows.sorted { $0.occurredAt == $1.occurredAt ? $0.id < $1.id : $0.occurredAt < $1.occurredAt }
    }
}
