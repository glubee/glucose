import SwiftUI
import UIKit

struct RecognitionResultView: View {
    @State private var viewModel: RecognitionResultViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsDeleteConfirm = false
    @State private var showsDeleteError = false
    private let previewImage: UIImage?
    private let onDeletePhoto: (() -> Bool)?
    let onSaved: () -> Void

    init(photoId: UUID, context: IntakeContext, occurredAt: Date = .now, previewImage: UIImage? = nil,
         onDeletePhoto: (() -> Bool)? = nil, onSaved: @escaping () -> Void) {
        _viewModel = State(initialValue: RecognitionResultViewModel(photoId: photoId, context: context, occurredAt: occurredAt))
        self.previewImage = previewImage
        self.onDeletePhoto = onDeletePhoto
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if viewModel.isPreview {
                        Label("미리보기 화면이에요. 실제 기록은 저장하지 않아요.", systemImage: "eye")
                            .font(.caption1).foregroundStyle(Color.textSecondary)
                            .accessibilityIdentifier("recognitionPreviewNotice")
                    }
                    if let previewImage {
                        Image(uiImage: previewImage).resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                            .accessibilityLabel("확인 대기 사진")
                    }
                    switch viewModel.state {
                    case .polling:
                        VStack(spacing: Spacing.m) {
                            MascotView(pose: .magnifier, size: 140, floats: true)
                            Text("어떤 음식인지 보고 있어요").font(.headline2)
                            ProgressView().tint(Color.brand)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.xl)
                    case .notFoodPhoto:
                        notice("음식 사진이 아닌 것 같아요. 먹은 음식을 직접 적어주세요.")
                    case .failed(let message):
                        notice(message)
                    case .ready, .saving, .saved:
                        EmptyView()
                    }
                    if viewModel.state != .polling {
                        FoodRecordFields(draft: $viewModel.draft)
                            .disabled(isBusy || viewModel.state == .saved)
                    }
                    if onDeletePhoto != nil {
                        Button("사진 지우기", role: .destructive) { showsDeleteConfirm = true }
                            .font(.body2.weight(.semibold))
                            .foregroundStyle(Color.alert)
                            .frame(maxWidth: .infinity, minHeight: Metrics.minTapTarget)
                            .disabled(isBusy || viewModel.state == .saved)
                            .accessibilityIdentifier("deletePendingPhoto")
                    }
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.m)
            }
            .scrollDismissesKeyboard(.interactively)

            if viewModel.state != .polling {
                VStack(spacing: Spacing.xs) {
                    if let message = viewModel.saveErrorMessage {
                        Text(message).font(.caption1).foregroundStyle(Color.alert)
                    }
                    Button {
                        Task {
                            if await viewModel.confirm() { onSaved() }
                        }
                    } label: {
                        if isBusy { ProgressView().tint(Color.onButton) }
                        else { Text("이대로 저장하기") }
                    }
                    .buttonStyle(canSave || isBusy ? .glubeePrimary : .glubeeMuted)
                    .disabled(!canSave)
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.s)
            }
        }
        .background(Color.canvas)
        .navigationTitle("음식 확인")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isBusy)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") { dismiss() }.disabled(isBusy)
            }
        }
        .interactiveDismissDisabled(isBusy)
        .alert("이 사진을 지울까요?", isPresented: $showsDeleteConfirm) {
            Button("사진 지우기", role: .destructive) {
                guard !isBusy else { return }
                showsDeleteError = onDeletePhoto?() == false
            }
            Button("취소", role: .cancel) {}
        } message: { Text(PendingPhotoDeletion.message) }
        .alert("사진을 지우지 못했어요. 다시 시도해 주세요.", isPresented: $showsDeleteError) {
            Button("확인", role: .cancel) {}
        }
        .task { await viewModel.loadRecognition() }
    }

    private var isBusy: Bool { viewModel.state == .saving }
    private var canSave: Bool {
        guard !viewModel.isPreview else { return false }
        return switch viewModel.state {
        case .ready, .notFoodPhoto, .failed: viewModel.isSaveEnabled
        default: false
        }
    }

    private func notice(_ text: String) -> some View {
        HStack(spacing: Spacing.s) {
            MascotView(pose: .think, size: 56)
            Text(text).font(.body2).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.textPrimary)
        .card(.brand, padding: Spacing.s)
    }
}

#Preview {
    NavigationStack { RecognitionResultView(photoId: UUID(), context: .meal) {} }
}
