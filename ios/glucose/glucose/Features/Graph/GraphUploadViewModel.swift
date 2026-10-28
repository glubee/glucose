//
//  GraphUploadViewModel.swift
//  glucose
//
//  presigned URL 발급 -> R2에 PUT -> 완료 통보 -> 분석 결과 폴링(409면 지연 후 재시도).
//  날짜는 ml-service가 이미지에서 읽으므로 앱이 따로 보내지 않는다.
//

import Foundation

enum GraphUploadState: Equatable {
    case idle
    case uploading
    case analyzing
    case done(date: String, coverageRatio: Double)
    case failed(String)
}

@Observable
final class GraphUploadViewModel {

    private(set) var state: GraphUploadState = .idle
    private var task: Task<Void, Never>?
    private var uploadedId: UUID?

    var isBusy: Bool {
        state == .uploading || state == .analyzing
    }

    func start(imageData: Data, contentType: String) {
        task?.cancel()
        task = Task { [weak self] in
            await self?.run(imageData: imageData, contentType: contentType)
        }
    }

    func cancel() {
        task?.cancel()
    }

    func reset() {
        task?.cancel()
        uploadedId = nil
        state = .idle
    }

    private func run(imageData: Data, contentType: String) async {
        if let uploadedId {
            state = .analyzing
            do {
                let _: GraphReprocessResponse = try await APIClient.shared.send(
                    path: "/v1/glucose-graphs/\(uploadedId.uuidString)/reprocess", method: .post)
                guard !Task.isCancelled else { return }
                await poll(uploadId: uploadedId)
            } catch APIError.server(_, let body) {
                guard !Task.isCancelled else { return }
                if body.code == "GRAPH_SOURCE_NOT_FOUND" { self.uploadedId = nil }
                state = .failed(Self.failureMessage(forCode: body.code))
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed("다시 분석하지 못했어요. 잠시 후 다시 시도해 주세요.")
            }
            return
        }
        state = .uploading
        let uploadId: UUID
        do {
            let started: GraphUploadStartResponse = try await APIClient.shared.send(
                path: "/v1/glucose-graphs",
                method: .post,
                body: StartGraphUploadRequest(contentType: contentType)
            )
            try Task.checkCancellation()
            try await putToR2(data: imageData, url: started.uploadUrl, contentType: contentType)
            try Task.checkCancellation()
            try await APIClient.shared.sendVoid(
                path: "/v1/glucose-graphs/\(started.uploadId.uuidString)/complete",
                method: .post
            )
            try Task.checkCancellation()
            uploadId = started.uploadId
            uploadedId = uploadId
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed("업로드에 실패했습니다. 다시 시도해주세요.")
            return
        }

        state = .analyzing
        await poll(uploadId: uploadId)
    }

    private func poll(uploadId: UUID) async {
        var delayNanoseconds: UInt64 = 1_000_000_000
        let maxDelayNanoseconds: UInt64 = 5_000_000_000

        while !Task.isCancelled {
            do {
                let result: GraphStatusResponse = try await APIClient.shared.send(
                    path: "/v1/glucose-graphs/\(uploadId.uuidString)"
                )
                guard !Task.isCancelled else { return }
                state = .done(date: result.date, coverageRatio: result.coverageRatio)
                return
            } catch APIError.server(409, _) {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
                delayNanoseconds = min(delayNanoseconds * 2, maxDelayNanoseconds)
            } catch APIError.server(_, let body) {
                state = .failed(Self.failureMessage(forCode: body.code))
                return
            } catch {
                state = .failed("분석 결과를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.")
                return
            }
        }
    }

    private func putToR2(data: Data, url: URL, contentType: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
    }

    /// 서버 오류 코드(docs/backend-api.md 13번)를 사용자가 다음에 뭘 해야 할지 알 수 있는 문장으로 바꾼다.
    static func failureMessage(forCode code: String) -> String {
        switch code {
        case "GRAPH_NOT_RECOGNIZED":
            "이미지에서 날짜나 혈당 눈금을 읽지 못했어요. 날짜와 그래프 전체가 보이는 이미지를 선택해 주세요."
        case "GRAPH_DATE_NOT_RECOGNIZED":
            "이미지의 날짜를 읽지 못했어요. 상단 날짜가 선명하게 보이는지 확인해 주세요."
        case "GRAPH_AXES_NOT_RECOGNIZED":
            "혈당 눈금을 읽지 못했어요. 그래프의 위·아래 눈금이 모두 보이는지 확인해 주세요."
        case "GRAPH_PARSER_OUTDATED", "GRAPH_OCR_UNAVAILABLE":
            "그래프 분석을 지금 사용할 수 없어요. 잠시 후 다시 시도해 주세요."
        case "GRAPH_REPROCESS_REQUIRED":
            "그래프를 새로 읽어야 해요. 다시 시도를 누르면 저장된 원본으로 분석해요."
        case "GRAPH_SOURCE_NOT_FOUND":
            "저장된 원본을 찾지 못했어요. 이미지를 다시 올려 주세요."
        case "GRAPH_TOO_LITTLE_DATA":
            "그래프에 혈당 기록이 너무 적어요(하루의 10% 미만). 센서 기록이 더 쌓인 날의 그래프를 올려주세요."
        default:
            "그래프를 분석하지 못했어요. 잠시 후 다시 시도해주세요."
        }
    }
}
