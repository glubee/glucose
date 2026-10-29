//
//  RecordsViewModel.swift
//  glucose
//
//  intake/insulin-event는 서버에서 각각 독립적으로 cursor 페이지네이션된다.
//  두 스트림을 시간순으로 올바르게 병합하기 위해, 각자 버퍼를 두고 둘 중 더 최신인
//  항목만 하나씩 꺼내 보여준다(한쪽 버퍼가 비어있는데 그 소스가 아직 안 끝났으면
//  먼저 채운 뒤에만 비교한다 - 그래야 페이지 경계에서 순서가 뒤섞이지 않는다).
//

import Foundation

@MainActor
@Observable
final class RecordsViewModel {

    enum LoadState: Equatable {
        case idle
        case loaded
        case error(String)
    }

    private(set) var items: [RecordItem] = []
    private(set) var state: LoadState = .idle
    private(set) var isLoadingMore = false
    private(set) var hasMore = true
    private(set) var filter: RecordFilter = .all
    private var seenIDs = Set<String>()
    private var intakeCursors = Set<String>()
    private var insulinCursors = Set<String>()

    private let repository: RecordRepository
    private let pageSize = 20

    private var intakeBuffer: [RecordItem] = []
    private var insulinBuffer: [RecordItem] = []
    private var intakeCursor: String?
    private var insulinCursor: String?
    private var intakeExhausted = false
    private var insulinExhausted = false
    private var loadID = UUID()

    init(repository: RecordRepository? = nil) {
        self.repository = repository ?? RecordDataSource.repository
    }

    var isInitialLoading: Bool {
        items.isEmpty && isLoadingMore
    }

    func load(filter: RecordFilter? = nil) async {
        if let filter { self.filter = filter }
        loadID = UUID()
        intakeBuffer = []
        insulinBuffer = []
        intakeCursor = nil
        insulinCursor = nil
        intakeExhausted = self.filter == .insulin
        insulinExhausted = self.filter == .food || self.filter == .response
        seenIDs = []
        intakeCursors = []
        insulinCursors = []
        hasMore = true
        items = []
        state = .idle
        await fetchMore()
    }

    func refresh() async {
        await load()
    }

    func loadNextPage() async {
        guard hasMore, !isLoadingMore else { return }
        await fetchMore()
    }

    func loadMoreIfNeeded(currentItem: RecordItem) async {
        guard hasMore, !isLoadingMore else { return }
        guard let index = items.firstIndex(where: { $0.timelineID == currentItem.timelineID }) else { return }
        if index >= items.count - 5 {
            await fetchMore()
        }
    }

    private func fetchMore() async {
        let activeID = loadID
        isLoadingMore = true
        defer { if activeID == loadID { isLoadingMore = false } }

        var newlyEmitted: [RecordItem] = []
        var refills = 0

        while newlyEmitted.count < pageSize {
            do {
                while intakeBuffer.isEmpty && !intakeExhausted {
                    refills += 1
                    guard refills <= 1000 else { throw APIError.invalidResponse }
                    guard try await refillIntake(activeID: activeID) else { return }
                }
                while insulinBuffer.isEmpty && !insulinExhausted {
                    refills += 1
                    guard refills <= 1000 else { throw APIError.invalidResponse }
                    guard try await refillInsulin(activeID: activeID) else { return }
                }
            } catch {
                guard activeID == loadID, !Task.isCancelled else { return }
                items.append(contentsOf: newlyEmitted)
                hasMore = hasRemainingData
                state = .error(Self.errorMessage(for: error))
                return
            }

            guard let next = popNextItem() else { break }
            if seenIDs.insert(TimelineEntry.record(next).id).inserted { newlyEmitted.append(next) }
        }

        guard activeID == loadID, !Task.isCancelled else { return }
        items.append(contentsOf: newlyEmitted)
        hasMore = hasRemainingData
        state = .loaded
    }

    private var hasRemainingData: Bool {
        !intakeBuffer.isEmpty || !insulinBuffer.isEmpty || !intakeExhausted || !insulinExhausted
    }

    private func popNextItem() -> RecordItem? {
        switch (intakeBuffer.first, insulinBuffer.first) {
        case (nil, nil):
            return nil
        case (let intake?, nil):
            intakeBuffer.removeFirst()
            return intake
        case (nil, let insulin?):
            insulinBuffer.removeFirst()
            return insulin
        case (let intake?, let insulin?):
            if intake.occurredAt >= insulin.occurredAt {
                intakeBuffer.removeFirst()
                return intake
            } else {
                insulinBuffer.removeFirst()
                return insulin
            }
        }
    }

    private func refillIntake(activeID: UUID) async throws -> Bool {
        let page = try await repository.fetchIntakePage(cursor: intakeCursor, limit: pageSize)
        guard activeID == loadID, !Task.isCancelled else { return false }
        if let next = page.nextCursor, !intakeCursors.insert(next).inserted { throw APIError.invalidResponse }
        intakeBuffer.append(contentsOf: page.items.filter { filter.includes($0) })
        intakeCursor = page.nextCursor
        if page.nextCursor == nil { intakeExhausted = true }
        return true
    }

    private func refillInsulin(activeID: UUID) async throws -> Bool {
        let page = try await repository.fetchInsulinPage(cursor: insulinCursor, limit: pageSize)
        guard activeID == loadID, !Task.isCancelled else { return false }
        if let next = page.nextCursor, !insulinCursors.insert(next).inserted { throw APIError.invalidResponse }
        insulinBuffer.append(contentsOf: page.items.filter { filter.includes($0) })
        insulinCursor = page.nextCursor
        if page.nextCursor == nil { insulinExhausted = true }
        return true
    }

    private static func errorMessage(for error: Error) -> String {
        guard let apiError = error as? APIError else { return "기록을 불러오지 못했어요." }
        switch apiError {
        case .network:
            return "네트워크 연결을 확인해주세요."
        case .notAuthenticated:
            return "로그인이 필요합니다."
        default:
            return "기록을 불러오지 못했어요."
        }
    }
}
