import Foundation

@MainActor
@Observable
final class FoodRecordFormViewModel {
    enum Mode: Equatable { case create, edit(id: UUID) }

    let mode: Mode
    var draft: FoodRecordDraft
    private(set) var isLoading = false
    private(set) var hasLoadedDetail: Bool
    private(set) var isSaving = false
    private(set) var isDeleting = false
    private(set) var hasCompleted = false
    private(set) var errorMessage: String?

    private let service: IntakeServing
    private let changes: RecordChanges

    init(record: IntakeRecord? = nil, service: IntakeServing? = nil, changes: RecordChanges? = nil) {
        mode = record.map { .edit(id: $0.id) } ?? .create
        draft = record.map(FoodRecordDraft.init(record:)) ?? FoodRecordDraft()
        hasLoadedDetail = record == nil
        self.service = service ?? RecordDataSource.intakeService
        self.changes = changes ?? .shared
    }

    var isBusy: Bool { isLoading || isSaving || isDeleting }
    var isSaveEnabled: Bool { hasLoadedDetail && draft.isValid && !isBusy && !hasCompleted }

    func load() async {
        guard case .edit(let id) = mode, !hasLoadedDetail, !isBusy, !hasCompleted else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await service.get(id: id)
            draft = FoodRecordDraft(record: response.toRecord())
            hasLoadedDetail = true
        } catch {
            errorMessage = "기록을 불러오지 못했어요. 다시 시도해 주세요."
        }
    }

    func save() async -> Bool {
        guard isSaveEnabled else { return false }
        isSaving = true
        errorMessage = nil
        let request = draft.request
        defer { isSaving = false }
        do {
            let response: IntakeResponse
            switch mode {
            case .create: response = try await service.create(request)
            case .edit(let id): response = try await service.update(id: id, request: request)
            }
            hasCompleted = true
            changes.publish(mode == .create ? .created : .updated, recordID: response.id)
            return true
        } catch APIError.notAuthenticated {
            errorMessage = "로그인한 뒤 다시 저장해 주세요. 입력한 내용은 그대로 있어요."
            return false
        } catch {
            errorMessage = "저장하지 못했어요. 입력한 내용은 그대로 있어요. 다시 시도해 주세요."
            return false
        }
    }

    func delete() async -> Bool {
        guard case .edit(let id) = mode, hasLoadedDetail, !isBusy, !hasCompleted else { return false }
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            try await service.delete(id: id)
            hasCompleted = true
            changes.publish(.deleted, recordID: id)
            return true
        } catch {
            errorMessage = "지우지 못했어요. 기록은 그대로 있어요. 다시 시도해 주세요."
            return false
        }
    }
}
