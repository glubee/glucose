import Foundation

/// 기기에만 보호해 저장한다. 서명된 URL은 로그나 서버 기록 요청에 넣지 않는다.
struct PhotoUploadCheckpoint: Codable, Hashable {
    let photoId: UUID
    let uploadURL: URL
    let expiresAt: Date
    var didUpload = false
}

@MainActor
protocol PhotoUploading {
    func upload(imageData: Data, context: IntakeContext, capturedAt: Date, clientID: UUID, checkpoint: PhotoUploadCheckpoint?,
                onCheckpoint: @escaping (PhotoUploadCheckpoint) throws -> Void) async throws -> UUID
    func upload(imageData: Data, context: IntakeContext, checkpoint: PhotoUploadCheckpoint?,
                onCheckpoint: @escaping (PhotoUploadCheckpoint) throws -> Void) async throws -> UUID
}

extension PhotoUploading {
    func upload(imageData: Data, context: IntakeContext, capturedAt: Date, clientID: UUID, checkpoint: PhotoUploadCheckpoint?,
                onCheckpoint: @escaping (PhotoUploadCheckpoint) throws -> Void) async throws -> UUID {
        try await upload(imageData: imageData, context: context, checkpoint: checkpoint, onCheckpoint: onCheckpoint)
    }
}

@MainActor
protocol PhotoUploadTransport {
    func start(context: IntakeContext, capturedAt: Date?, clientID: UUID?) async throws -> PhotoUploadCheckpoint
    func start(context: IntakeContext) async throws -> PhotoUploadCheckpoint
    func put(imageData: Data, url: URL, onProgress: @escaping @MainActor @Sendable (Double) -> Void) async throws
    func complete(photoId: UUID) async throws
}

extension PhotoUploadTransport {
    func start(context: IntakeContext, capturedAt: Date?, clientID: UUID?) async throws -> PhotoUploadCheckpoint {
        try await start(context: context)
    }
}

@MainActor
final class PhotoUploader: PhotoUploading {
    var onProgress: ((Double) -> Void)?
    var onCompleting: (() -> Void)?
    private let transport: PhotoUploadTransport?

    init(transport: PhotoUploadTransport? = nil) {
        self.transport = transport
    }

    func upload(imageData: Data, context: IntakeContext, checkpoint: PhotoUploadCheckpoint? = nil,
                onCheckpoint: @escaping (PhotoUploadCheckpoint) throws -> Void = { _ in }) async throws -> UUID {
        try await uploadWithMetadata(imageData: imageData, context: context, capturedAt: nil, clientID: nil, checkpoint: checkpoint, onCheckpoint: onCheckpoint)
    }

    func upload(imageData: Data, context: IntakeContext, capturedAt: Date, clientID: UUID, checkpoint: PhotoUploadCheckpoint?,
                onCheckpoint: @escaping (PhotoUploadCheckpoint) throws -> Void) async throws -> UUID {
        try await uploadWithMetadata(imageData: imageData, context: context, capturedAt: capturedAt, clientID: clientID, checkpoint: checkpoint, onCheckpoint: onCheckpoint)
    }
    private func uploadWithMetadata(imageData: Data, context: IntakeContext, capturedAt: Date?, clientID: UUID?, checkpoint: PhotoUploadCheckpoint?,
                onCheckpoint: @escaping (PhotoUploadCheckpoint) throws -> Void) async throws -> UUID {
        let accountGeneration = AuthSession.shared.generation
        let transport = self.transport ?? LivePhotoUploadTransport(sessionGeneration: accountGeneration)
        func check() throws {
            try Task.checkCancellation()
            guard AuthSession.shared.generation == accountGeneration else { throw CancellationError() }
        }
        try check()
        var current = checkpoint
        if let existing = current {
            // PUT/완료 응답을 잃었을 수 있다. 멱등인 완료 통보로 먼저 서버 상태를 확인한다.
            onCompleting?()
            do {
                try await transport.complete(photoId: existing.photoId)
                try check()
                return existing.photoId
            } catch APIError.server(409, let body) where body.code == "PHOTO_NOT_UPLOADED" {
                // 실제 바이트가 없다는 응답일 때만 전송한다. 만료된 URL은 새로 발급받는다.
                current?.didUpload = false
                if existing.expiresAt <= .now { current = nil }
            }
        }
        try check()
        if current == nil {
            current = try await transport.start(context: context, capturedAt: capturedAt, clientID: clientID)
            try check()
            try onCheckpoint(current!)
        }
        guard var ticket = current else { throw APIError.invalidResponse }
        try check()
        if !ticket.didUpload {
            try await transport.put(imageData: imageData, url: ticket.uploadURL) { [weak self] fraction in self?.onProgress?(fraction) }
            try check()
            ticket.didUpload = true
            try onCheckpoint(ticket)
        }
        try check()
        onCompleting?()
        try await transport.complete(photoId: ticket.photoId)
        try check()
        return ticket.photoId
    }
}

@MainActor
private struct LivePhotoUploadTransport: PhotoUploadTransport {
    let sessionGeneration: UUID
    func start(context: IntakeContext) async throws -> PhotoUploadCheckpoint {
        try await start(context: context, capturedAt: nil, clientID: nil)
    }
    func start(context: IntakeContext, capturedAt: Date?, clientID: UUID?) async throws -> PhotoUploadCheckpoint {
        let response: PhotoUploadStartResponse = try await APIClient.shared.send(
            path: "/v1/photos", method: .post,
            body: StartPhotoUploadRequest(contentType: "image/jpeg", context: context.rawValue, capturedAt: capturedAt, clientId: clientID), expectedSession: sessionGeneration)
        return PhotoUploadCheckpoint(photoId: response.photoId, uploadURL: response.uploadUrl,
                                     expiresAt: .now.addingTimeInterval(TimeInterval(response.expiresIn)), didUpload: response.uploaded == true)
    }

    func put(imageData: Data, url: URL, onProgress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        let delegate = PhotoUploadProgressDelegate(onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        // async upload은 Task 취소를 실제 HTTP 작업에 전달한다.
        let (_, response) = try await session.upload(for: request, from: imageData)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
    }

    func complete(photoId: UUID) async throws {
        try await APIClient.shared.sendVoid(path: "/v1/photos/\(photoId.uuidString)/complete", method: .post, expectedSession: sessionGeneration)
    }
}

private final class PhotoUploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let onProgress: @MainActor (Double) -> Void

    init(onProgress: @escaping @MainActor (Double) -> Void) { self.onProgress = onProgress }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                               didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                               totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        let fraction = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        Task { @MainActor [self] in onProgress(fraction) }
    }
}
