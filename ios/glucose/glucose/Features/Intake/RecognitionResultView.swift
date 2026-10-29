import SwiftUI

struct RecognitionResultView: View {
    @State private var viewModel: RecognitionResultViewModel
    @Environment(\.dismiss) private var dismiss
    let onSaved: () -> Void

    init(photoId: UUID, context: IntakeContext, occurredAt: Date = .now, onSaved: @escaping () -> Void) {
        _viewModel = State(initialValue: RecognitionResultViewModel(photoId: photoId, context: context, occurredAt: occurredAt))
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
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
        .task { await viewModel.loadRecognition() }
    }

    private var isBusy: Bool { viewModel.state == .saving }
    private var canSave: Bool {
        switch viewModel.state {
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
