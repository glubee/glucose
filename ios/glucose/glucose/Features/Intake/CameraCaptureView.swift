//
//  CameraCaptureView.swift
//  glucose
//

import SwiftUI
import UIKit

struct CameraCaptureView: UIViewControllerRepresentable {
    /// 카메라가 없는 기기(시뮬레이터)에서는 .photoLibrary로 대신한다
    var sourceType: UIImagePickerController.SourceType = .camera
    let onCapture: (UIImage) -> Void
    var onCancel: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let onCancel: (() -> Void)?

        init(onCapture: @escaping (UIImage) -> Void, onCancel: (() -> Void)?) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            if let onCancel {
                onCancel()
            } else {
                picker.dismiss(animated: true)
            }
        }
    }
}
