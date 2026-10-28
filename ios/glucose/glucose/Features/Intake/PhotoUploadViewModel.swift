//
//  PhotoUploadViewModel.swift
//  glucose
//
//  사진 기록 화면의 업로드 상태. 실제 업로드는 PhotoUploader가 한다.
//  실패하면 사용자가 "다시 시도"를 눌러야 한다(자동 재시도 없음).
//

import Foundation

enum PhotoUploadState: Equatable {
    case idle
    case starting
    case uploading(progress: Double)
    case completing
    case done
    case failed(String)
}

@Observable
final class PhotoUploadViewModel {

    private(set) var state: PhotoUploadState = .idle
    private(set) var photoId: UUID?

    func upload(imageData: Data, context: IntakeContext) async {
        state = .starting
        let uploader = PhotoUploader()
        uploader.onProgress = { fraction in
            Task { @MainActor [weak self] in self?.state = .uploading(progress: fraction) }
        }
        uploader.onCompleting = {
            Task { @MainActor [weak self] in self?.state = .completing }
        }
        do {
            photoId = try await uploader.upload(imageData: imageData, context: context)
            state = .done
        } catch {
            state = .failed("업로드에 실패했습니다. 다시 시도해주세요.")
        }
    }
}
