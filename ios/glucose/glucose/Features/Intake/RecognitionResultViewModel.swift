import Foundation

enum RecognitionResultState: Equatable {
    case polling
    case ready
    case notFoodPhoto
    case failed(String)
    case saving
    case saved
}

@MainActor
@Observable
final class RecognitionResultViewModel {
    let photoId: UUID
    var draft: FoodRecordDraft
    private(set) var state: RecognitionResultState = .polling
    private(set) var saveErrorMessage: String?

    private let service: IntakeServing
    private let changes: RecordChanges

    init(photoId: UUID, context: IntakeContext, occurredAt: Date = .now,
         service: IntakeServing? = nil, changes: RecordChanges? = nil) {
        self.photoId = photoId
        draft = FoodRecordDraft(context: context, occurredAt: occurredAt, photoId: photoId, items: [])
        self.service = service ?? IntakeService()
        self.changes = changes ?? .shared
    }

    var items: [EditableFoodItem] { draft.items }
    var isSaveEnabled: Bool { draft.isValid }
    var isPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-recognition")
        #else
        false
        #endif
    }

    /// 화면을 닫으면 SwiftUI task와 함께 결과 조회도 취소된다.
    func loadRecognition() async {
        guard state == .polling else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-recognition") {
            draft.items = [
                EditableFoodItem(name: "김밥", count: 1, unit: "줄", categoryHint: nil, tags: []),
                EditableFoodItem(name: "오렌지 주스", count: 1, unit: "잔", categoryHint: nil, tags: [])
            ]
            state = .ready
            return
        }
        #endif
        var delay: UInt64 = 1_000_000_000
        while !Task.isCancelled {
            do {
                let result = try await service.recognize(photoId: photoId)
                guard !Task.isCancelled else { return }
                draft.items = result.items.map(\.asEditableItem)
                state = result.isFoodPhoto ? .ready : .notFoodPhoto
                return
            } catch is CancellationError {
                return
            } catch APIError.server(409, let body) where body.code == "RECOGNITION_NOT_READY" {
                do { try await Task.sleep(nanoseconds: delay) } catch { return }
                delay = min(delay * 2, 5_000_000_000)
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed("결과를 불러오지 못했어요.\n먹은 음식을 직접 적어주세요.")
                return
            }
        }
    }

    func addBlankItem() { draft.items.append(.blank()) }

    func removeItem(id: EditableFoodItem.ID) { draft.items.removeAll { $0.id == id } }

    func updateItem(id: EditableFoodItem.ID, name: String? = nil, count: Int? = nil, unit: String? = nil) {
        guard let index = draft.items.firstIndex(where: { $0.id == id }) else { return }
        if let name { draft.items[index].name = name }
        if let count { draft.items[index].count = count }
        if let unit { draft.items[index].unit = unit }
    }

    func confirm() async -> Bool {
        guard !isPreview else { return false }
        guard isSaveEnabled, state != .polling, state != .saving, state != .saved else { return false }
        state = .saving
        saveErrorMessage = nil
        let request = draft.request
        do {
            _ = try await service.create(request)
            state = .saved
            changes.publish(.created)
            return true
        } catch {
            saveErrorMessage = "저장하지 못했어요. 입력한 내용은 그대로 있어요. 다시 시도해 주세요."
            state = .ready
            return false
        }
    }
}
