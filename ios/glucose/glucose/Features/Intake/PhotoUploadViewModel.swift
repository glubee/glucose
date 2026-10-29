import Foundation

enum PhotoUploadState: Equatable {
    case idle, starting
    case uploading(progress: Double)
    case completing, done
    case failed(String)
}

@MainActor
@Observable
final class PhotoUploadViewModel {
    private(set) var state: PhotoUploadState = .idle
    private(set) var photoId: UUID?
    private var checkpoint: PhotoUploadCheckpoint?
    private var operationID = UUID()
    private let uploader: PhotoUploader

    init(uploader: PhotoUploader? = nil) { self.uploader = uploader ?? PhotoUploader() }

    var isInFlight: Bool {
        switch state {
        case .starting, .uploading, .completing: true
        default: false
        }
    }

    func reset() {
        guard !isInFlight else { return }
        operationID = UUID()
        checkpoint = nil
        photoId = nil
        state = .idle
    }

    func upload(imageData: Data, context: IntakeContext) async {
        guard !isInFlight, state != .done else { return }
        let activeID = UUID()
        operationID = activeID
        state = .starting
        uploader.onProgress = { [weak self] fraction in
            guard let self, operationID == activeID, isInFlight else { return }
            state = .uploading(progress: fraction)
        }
        uploader.onCompleting = { [weak self] in
            guard let self, operationID == activeID, isInFlight else { return }
            state = .completing
        }
        do {
            let id = try await uploader.upload(imageData: imageData, context: context, checkpoint: checkpoint) { [self] value in
                checkpoint = value
            }
            guard operationID == activeID else { return }
            photoId = id
            state = .done
        } catch {
            guard operationID == activeID else { return }
            state = .failed("올리지 못했어요. 사진은 그대로 있어요. 다시 시도해 주세요.")
        }
    }
}
