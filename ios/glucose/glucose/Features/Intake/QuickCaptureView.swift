import SwiftUI
import UIKit

struct QuickCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: QuickCaptureViewModel

    init(viewModel: QuickCaptureViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? QuickCaptureViewModel())
    }

    private var sourceType: UIImagePickerController.SourceType {
        UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
    }

    var body: some View {
        Group {
            if let image = viewModel.captured { done(image) }
            else {
                CameraCaptureView(sourceType: sourceType, onCapture: viewModel.capture, onCancel: { dismiss() })
                    .ignoresSafeArea()
            }
        }
        .task(id: viewModel.captureID) {
            if await viewModel.waitForAutoClose() { dismiss() }
        }
    }

    private func done(_ image: UIImage) -> some View {
        VStack(spacing: Spacing.m) {
            Spacer()
            Image(uiImage: image)
                .resizable().scaledToFill()
                .frame(width: 180, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sheet))
                .accessibilityHidden(true)
            MascotView(pose: viewModel.failed ? .sulky : .camera, size: 120, motion: .pop)
            Text(viewModel.failed ? "사진을 저장하지 못했어요" : "찰칵! 밤에 같이 확인해요")
                .font(.pretendard(22, relativeTo: .title2, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
            if let message = viewModel.errorMessage {
                Text(message).font(.body2).foregroundStyle(Color.alert)
            } else {
                Text("3초 뒤 이전 화면으로 돌아가요.")
                    .font(.caption1).foregroundStyle(Color.textSecondary)
            }
            Button("다시 찍기") { viewModel.retake() }
                .buttonStyle(.glubeePrimary)
                .accessibilityIdentifier("quickRetake")
            Button("닫기") { dismiss() }
                .buttonStyle(.glubeeSoft)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.gutter)
        .background(Color.canvas)
        .sensoryFeedback(.success, trigger: viewModel.pendingId)
    }
}
