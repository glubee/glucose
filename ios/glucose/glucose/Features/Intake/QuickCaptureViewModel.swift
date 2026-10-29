import Foundation
import UIKit

@MainActor
@Observable
final class QuickCaptureViewModel {
    private(set) var captured: UIImage?
    private(set) var pendingId: UUID?
    private(set) var captureID = UUID()
    private(set) var errorMessage: String?
    private var allowsAutoClose = false
    private let store: PendingPhotoStore

    init(store: PendingPhotoStore? = nil) { self.store = store ?? RecordDataSource.photos }

    var failed: Bool { captured != nil && pendingId == nil }

    func capture(_ image: UIImage) {
        guard captured == nil else { return }
        captured = image
        captureID = UUID()
        errorMessage = nil
        guard let data = ImageResizer.prepareForUpload(image),
              let photo = store.add(imageData: data, context: .meal) else {
            errorMessage = "사진을 저장하지 못했어요. 다시 찍어주세요."
            return
        }
        pendingId = photo.id
        allowsAutoClose = true
    }

    @discardableResult
    func retake() -> Bool {
        // 실패한 재촬영도 기존 타이머를 멈춘다. 오류를 읽는 중 화면이 닫히면 안 된다.
        captureID = UUID()
        allowsAutoClose = false
        if let pendingId, store.photos.contains(where: { $0.id == pendingId }), !store.remove(pendingId) {
            errorMessage = store.errorMessage
            return false
        }
        pendingId = nil
        captured = nil
        errorMessage = nil
        return true
    }

    func waitForAutoClose(after delay: Duration = .seconds(3)) async -> Bool {
        guard allowsAutoClose, errorMessage == nil, captured != nil, pendingId != nil, !failed else { return false }
        let expected = captureID
        do { try await Task.sleep(for: delay) } catch { return false }
        return !Task.isCancelled && allowsAutoClose && errorMessage == nil
            && captureID == expected && captured != nil && pendingId != nil
    }
}
