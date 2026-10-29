//
//  PhotoCaptureViewModel.swift
//  glucose
//
//  PhotosUI 타입은 일부러 안 쓴다 - 사진 선택/로드는 View(PhotoCaptureView)가 하고,
//  여기엔 UIImage만 넘어온다. (PhotosPickerItem을 여기서 직접 쓰면 "Cannot find type
//  'PhotosPickerItem' in scope" 빌드 에러가 나는 걸 실기기에서 확인함 — 원인 불명이라
//  PhotosUI 의존 자체를 View로 옮겨 피해감)
//

import Foundation
import UIKit

@Observable
final class PhotoCaptureViewModel {

    var context: IntakeContext = .meal

    private(set) var previewImage: UIImage?
    private(set) var processedData: Data?
    private(set) var processedSizeDescription: String?
    private(set) var errorMessage: String?
    private var selectionID = UUID()

    func beginSelection() -> UUID {
        selectionID = UUID()
        return selectionID
    }

    func invalidateSelection() { selectionID = UUID() }

    @discardableResult
    func process(_ image: UIImage, selectionID: UUID) -> Bool {
        guard selectionID == self.selectionID else { return false }
        process(image)
        return true
    }

    var isReadyForUpload: Bool { processedData != nil }

    func process(_ image: UIImage) {
        invalidateSelection()
        errorMessage = nil
        previewImage = image

        guard let data = ImageResizer.prepareForUpload(image) else {
            errorMessage = "사진을 처리하지 못했어요. 다른 사진을 골라주세요."
            processedData = nil
            processedSizeDescription = nil
            return
        }

        processedData = data
        processedSizeDescription = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }

    func setError(_ message: String) {
        errorMessage = message
    }

    func reset() {
        previewImage = nil
        processedData = nil
        processedSizeDescription = nil
        errorMessage = nil
    }
}
