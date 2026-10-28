//
//  QuickCaptureView.swift
//  glucose
//
//  위젯에서 여는 빠른 촬영. 찍으면 짧은 완료 화면만 보여주고 닫는다.
//  음식 확인은 하루 마무리에서 한다(docs/ios-design-v4.md 0장).
//

import SwiftUI
import UIKit

struct QuickCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var captured: UIImage?
    @State private var pendingId: UUID?
    /// 빠른 촬영은 식사로 저장하고, 상황은 하루 마무리의 음식 확인에서 고친다
    private let context: IntakeContext = .meal
    @State private var failed = false

    private static let autoCloseSeconds: Double = 1.8

    private var sourceType: UIImagePickerController.SourceType {
        UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
    }

    var body: some View {
        if let captured {
            done(captured)
        } else {
            CameraCaptureView(sourceType: sourceType, onCapture: save, onCancel: { dismiss() })
                .ignoresSafeArea()
        }
    }

    private func save(_ image: UIImage) {
        captured = image
        guard let data = ImageResizer.prepareForUpload(image),
              let photo = PendingPhotoStore.shared.add(imageData: data, context: context) else {
            failed = true
            return
        }
        pendingId = photo.id
    }

    @ViewBuilder
    private func done(_ image: UIImage) -> some View {
        // v5 프로토타입: 사진 + 카메라 든 글루비 + 한 줄 + 작은 닫기. 1.8초 뒤 저절로 닫힌다
        VStack(spacing: Spacing.m) {
            Spacer()
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 180, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sheet))
                .accessibilityHidden(true)
            MascotView(pose: failed ? .sulky : .camera, size: 120, motion: .pop)
            Text(failed ? "사진을 저장하지 못했어요.\n다시 찍어주세요." : "찰칵! 밤에 같이 확인해요")
                .font(.pretendard(22, relativeTo: .title2, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
            Button("닫기") { dismiss() }
                .buttonStyle(.glubeeSoft)
                .frame(width: 120)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.gutter)
        .background(Color.canvas)
        .sensoryFeedback(.success, trigger: pendingId)
        .task {
            guard !failed else { return }
            try? await Task.sleep(for: .seconds(Self.autoCloseSeconds))
            dismiss()
        }
    }
}
