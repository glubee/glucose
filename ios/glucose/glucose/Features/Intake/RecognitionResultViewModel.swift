//
//  RecognitionResultViewModel.swift
//  glucose
//
//  사진 업로드 후 음식 인식 job을 폴링한다(409 RECOGNITION_NOT_READY면 지연 후 재시도).
//  결과는 제안일 뿐이고 사용자가 이름·개수를 수정/삭제/추가한 뒤 POST /v1/intakes로 확정한다.
//

import Foundation

enum RecognitionResultState: Equatable {
    case polling
    case ready
    case notFoodPhoto
    case failed(String)
    case saving
    case saved
}

@Observable
final class RecognitionResultViewModel {

    let photoId: UUID
    let context: IntakeContext
    /// 먹은 시각. 빠른 촬영 사진은 촬영 시각으로 시작하고, 사용자가 고칠 수 있다
    var occurredAt: Date

    private(set) var state: RecognitionResultState = .polling
    private(set) var items: [EditableFoodItem] = []
    private(set) var saveErrorMessage: String?

    private var pollTask: Task<Void, Never>?

    init(photoId: UUID, context: IntakeContext, occurredAt: Date = .now) {
        self.photoId = photoId
        self.context = context
        self.occurredAt = occurredAt
    }

    var isSaveEnabled: Bool {
        !items.isEmpty && items.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    func startPolling() {
        pollTask?.cancel()
        state = .polling
        pollTask = Task { [weak self] in
            await self?.poll()
        }
    }

    func cancelPolling() {
        pollTask?.cancel()
    }

    private func poll() async {
        #if DEBUG
        // 실행 인자 -recognition: 로그인 없이 인식 결과 화면 보기(예시 음식 2개)
        if ProcessInfo.processInfo.arguments.contains("-recognition") {
            items = [
                EditableFoodItem(name: "김밥", count: 1, unit: "줄", categoryHint: nil, tags: []),
                EditableFoodItem(name: "오렌지 주스", count: 1, unit: "잔", categoryHint: nil, tags: []),
            ]
            state = .ready
            return
        }
        #endif
        var delayNanoseconds: UInt64 = 1_000_000_000
        let maxDelayNanoseconds: UInt64 = 5_000_000_000

        while !Task.isCancelled {
            do {
                let result: RecognitionResponse = try await APIClient.shared.send(
                    path: "/v1/photos/\(photoId.uuidString)/recognition"
                )
                items = result.items.map(\.asEditableItem)
                state = result.isFoodPhoto ? .ready : .notFoodPhoto
                return
            } catch APIError.server(let status, let body) where status == 409 {
                _ = body
                try? await Task.sleep(nanoseconds: delayNanoseconds)
                delayNanoseconds = min(delayNanoseconds * 2, maxDelayNanoseconds)
            } catch APIError.server(422, _) {
                state = .failed("음식을 알아보지 못했어요.\n먹은 음식을 직접 적어주세요.")
                return
            } catch {
                state = .failed("결과를 불러오지 못했어요.\n먹은 음식을 직접 적어주세요.")
                return
            }
        }
    }

    func addBlankItem() {
        items.append(.blank())
    }

    func removeItem(id: EditableFoodItem.ID) {
        items.removeAll { $0.id == id }
    }

    func updateItem(id: EditableFoodItem.ID, name: String? = nil, count: Int? = nil, unit: String? = nil) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if let name { items[index].name = name }
        if let count { items[index].count = max(1, count) }
        if let unit { items[index].unit = unit }
    }

    func confirm() async -> Bool {
        state = .saving
        saveErrorMessage = nil
        do {
            let request = CreateIntakeRequest(
                context: context.rawValue,
                occurredAt: occurredAt,
                photoId: photoId,
                items: items.map { $0.toRequest() }
            )
            let _: IntakeResponse = try await APIClient.shared.send(path: "/v1/intakes", method: .post, body: request)
            state = .saved
            await MainActor.run { WidgetSnapshot.refresh(noteRecord: true) }
            return true
        } catch {
            saveErrorMessage = "저장하지 못했어요. 다시 눌러주세요."
            state = .ready
            return false
        }
    }
}
