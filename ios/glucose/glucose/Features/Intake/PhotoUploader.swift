//
//  PhotoUploader.swift
//  glucose
//
//  presigned URL 발급 -> R2에 직접 PUT -> 완료 통보 (docs/backend-api.md 8~9번).
//  서버는 바이트를 중계하지 않는다. 사진 기록 화면과 빠른 촬영이 같이 쓴다.
//

import Foundation

final class PhotoUploader: NSObject {

    /// R2 업로드 진행률(0~1). 메인 스레드가 아닐 수 있다
    var onProgress: ((Double) -> Void)?
    /// 완료 통보 직전에 부른다
    var onCompleting: (() -> Void)?

    /// 업로드가 끝나면 서버의 photoId를 돌려준다. 완료 통보가 끝나면 서버가 음식 인식을 시작한다
    func upload(imageData: Data, context: IntakeContext) async throws -> UUID {
        let started: PhotoUploadStartResponse = try await APIClient.shared.send(
            path: "/v1/photos",
            method: .post,
            body: StartPhotoUploadRequest(contentType: "image/jpeg", context: context.rawValue)
        )

        try await putToR2(data: imageData, url: started.uploadUrl, contentType: "image/jpeg")

        onCompleting?()
        try await APIClient.shared.sendVoid(
            path: "/v1/photos/\(started.photoId.uuidString)/complete",
            method: .post
        )
        return started.photoId
    }

    private func putToR2(data: Data, url: URL, contentType: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let task = session.uploadTask(with: request, from: data) { _, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    continuation.resume(throwing: APIError.invalidResponse)
                    return
                }
                continuation.resume()
            }
            task.resume()
        }
        session.finishTasksAndInvalidate()
    }
}

extension PhotoUploader: URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress?(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}
