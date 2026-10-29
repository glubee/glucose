import SwiftUI

struct FoodRecordFormView: View {
    @State private var viewModel: FoodRecordFormViewModel
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss
    private let onSaved: () -> Void
    private let onDeleted: () -> Void

    init(record: IntakeRecord? = nil, onSaved: @escaping () -> Void = {}, onDeleted: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: FoodRecordFormViewModel(record: record))
        self.onSaved = onSaved
        self.onDeleted = onDeleted
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.l) {
                        if viewModel.isLoading {
                            StateView(kind: .loading, title: "기록을 불러오고 있어요")
                        } else if viewModel.hasLoadedDetail {
                            FoodRecordFields(draft: $viewModel.draft)
                                .disabled(viewModel.isBusy || viewModel.hasCompleted)
                        }
                        if let message = viewModel.errorMessage {
                            Label(message, systemImage: "exclamationmark.circle")
                                .font(.body2)
                                .foregroundStyle(Color.alert)
                            if !viewModel.hasLoadedDetail {
                                Button("다시 불러오기") { Task { await viewModel.load() } }
                                    .buttonStyle(.glubeeSecondary)
                            }
                        }
                        if case .edit = viewModel.mode, viewModel.hasLoadedDetail {
                            Button("이 기록 지우기", role: .destructive) { showDeleteConfirm = true }
                                .font(.body2.weight(.semibold))
                                .foregroundStyle(Color.alert)
                                .frame(maxWidth: .infinity, minHeight: Metrics.minTapTarget)
                                .disabled(viewModel.isBusy || viewModel.hasCompleted)
                        }
                    }
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.vertical, Spacing.m)
                }
                .scrollDismissesKeyboard(.interactively)

                Button {
                    Task {
                        if await viewModel.save() {
                            onSaved()
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.isSaving { ProgressView().tint(Color.onButton) }
                    else { Text(viewModel.mode == .create ? "기록 남기기" : "변경 저장하기") }
                }
                .buttonStyle(viewModel.isSaveEnabled || viewModel.isSaving ? .glubeePrimary : .glubeeMuted)
                .disabled(!viewModel.isSaveEnabled)
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.s)
            }
            .background(Color.canvas)
            .navigationTitle(viewModel.mode == .create ? "글로 남기기" : "음식 기록 고치기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                        .disabled(viewModel.isSaving || viewModel.isDeleting)
                }
            }
            .confirmationDialog("이 음식 기록을 지울까요?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("기록 지우기", role: .destructive) {
                    Task {
                        if await viewModel.delete() {
                            onDeleted()
                            dismiss()
                        }
                    }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("지운 기록은 되돌릴 수 없어요.")
            }
            .interactiveDismissDisabled(viewModel.isSaving || viewModel.isDeleting)
            .task { await viewModel.load() }
        }
    }
}

#Preview { FoodRecordFormView() }
