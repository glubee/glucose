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
    @State private var context: IntakeContext = .meal
    @State private var failed = false
    /// 상황 칩을 만지면 자동으로 닫지 않는다
    @State private var userInteracted = false

    private static let autoCloseSeconds: Double = 3

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
        VStack(spacing: Spacing.l) {
            Spacer()

            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sheet))
                .accessibilityHidden(true)

            if failed {
                BeeSpeech(pose: .sulky, text: "사진을 저장하지 못했어요. 다시 찍어주세요.")
            } else {
                BeeSpeech(pose: .thumbsup, text: "찰칵! 밤에 같이 확인해요.")
                    .sensoryFeedback(.success, trigger: pendingId)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("어떤 상황이었어요? (선택)")
                        .font(.caption1)
                        .foregroundStyle(Color.textSecondary)
                    ChipPicker(
                        options: IntakeContext.allCases.map { ($0, $0.displayName) },
                        selection: Binding(
                            get: { context },
                            set: { newValue in
                                userInteracted = true
                                context = newValue
                                if let pendingId { PendingPhotoStore.shared.setContext(newValue, for: pendingId) }
                            }
                        )
                    )
                }
            }

            Spacer()

            Button("닫기") { dismiss() }.buttonStyle(.glubeePrimary)
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.bottom, Spacing.s)
        .background(Color.canvas)
        .task {
            guard !failed else { return }
            try? await Task.sleep(for: .seconds(Self.autoCloseSeconds))
            if !userInteracted { dismiss() }
        }
    }
}
