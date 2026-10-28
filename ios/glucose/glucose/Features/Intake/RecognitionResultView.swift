//
//  RecognitionResultView.swift
//  glucose
//
//  사진 -> 인식 결과 -> 수정 -> 저장을 한 흐름으로 잇는 화면(v5).
//  인식하는 동안은 돋보기 든 글루비, 끝나면 음식마다 카드(이름·개수), 아래에 먹은 시각과 저장 버튼.
//

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
                        polling
                    case .notFoodPhoto:
                        notice(pose: .think, text: "음식 사진이 아닌 것 같아요.\n먹은 음식을 직접 적어주세요.")
                        itemsSection
                    case .failed(let message):
                        notice(pose: .sulky, text: message)
                        itemsSection
                    case .ready, .saving, .saved:
                        itemsSection
                    }

                    if viewModel.state != .polling {
                        timeSection
                    }
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.m)
            }

            if viewModel.state != .polling {
                VStack(spacing: Spacing.xs) {
                    if let saveErrorMessage = viewModel.saveErrorMessage {
                        Text(saveErrorMessage).font(.caption1).foregroundStyle(Color.alert)
                    }
                    Button {
                        Task {
                            if await viewModel.confirm() {
                                onSaved()
                            }
                        }
                    } label: {
                        if isBusy { ProgressView().tint(Color.onButton) } else { Text("이대로 저장하기") }
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
                Button("취소") {
                    viewModel.cancelPolling()
                    dismiss()
                }
                .disabled(isBusy)
            }
        }
        .onAppear { viewModel.startPolling() }
    }

    private var isBusy: Bool {
        viewModel.state == .saving
    }

    private var canSave: Bool {
        switch viewModel.state {
        case .ready, .notFoodPhoto, .failed:
            return viewModel.isSaveEnabled
        default:
            return false
        }
    }

    // MARK: - 상태

    private var polling: some View {
        VStack(spacing: Spacing.m) {
            MascotView(pose: .magnifier, size: 140, floats: true)
            Text("어떤 음식인지 보고 있어요")
                .font(.headline2)
                .foregroundStyle(Color.textPrimary)
            ProgressView().tint(Color.brand)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.xl)
        .accessibilityElement(children: .combine)
    }

    private func notice(pose: MascotPose, text: String) -> some View {
        HStack(spacing: Spacing.s) {
            MascotView(pose: pose, size: 56)
            Text(text)
                .font(.body2)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .card(.brand, padding: Spacing.s)
    }

    // MARK: - 음식 목록

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "먹은 음식", subtitle: viewModel.items.isEmpty ? nil : "이름이나 개수가 다르면 고쳐주세요.")
            ForEach(viewModel.items) { item in
                itemRow(item)
            }
            Button {
                viewModel.addBlankItem()
            } label: {
                Label("음식 추가", systemImage: "plus")
            }
            .buttonStyle(.glubeeSecondary)
            .disabled(isBusy)
        }
    }

    private func itemRow(_ item: EditableFoodItem) -> some View {
        HStack(spacing: Spacing.s) {
            TextField("음식 이름", text: Binding(
                get: { item.name },
                set: { viewModel.updateItem(id: item.id, name: $0) }
            ))
            .font(.body1)
            .foregroundStyle(Color.textPrimary)
            .submitLabel(.done)

            HStack(spacing: Spacing.xxs) {
                countButton("minus", label: "\(item.name) 하나 빼기", disabled: item.count <= 1) {
                    viewModel.updateItem(id: item.id, count: item.count - 1)
                }
                Text("\(item.count)\(item.unit)")
                    .font(.body2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .frame(minWidth: 40)
                countButton("plus", label: "\(item.name) 하나 더하기", disabled: item.count >= 99) {
                    viewModel.updateItem(id: item.id, count: item.count + 1)
                }
            }

            Button {
                viewModel.removeItem(id: item.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: Metrics.minTapTarget, height: Metrics.minTapTarget)
            }
            .accessibilityLabel("\(item.name) 지우기")
        }
        .padding(.leading, Spacing.m)
        .padding(.vertical, Spacing.xxs)
        .frame(maxWidth: .infinity)
        .background(CardTone.plain.fill, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.line))
        .disabled(isBusy)
    }

    private func countButton(_ icon: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(disabled ? Color.textSecondary.opacity(0.4) : Color.textPrimary)
                .frame(width: 32, height: 32)
                .background(Color.surfaceMuted, in: Circle())
                .frame(width: Metrics.minTapTarget - 4, height: Metrics.minTapTarget)
        }
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    // MARK: - 먹은 시각

    private var timeSection: some View {
        HStack {
            Label("먹은 시각", systemImage: "clock")
                .font(.body1)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            DatePicker("먹은 시각", selection: $viewModel.occurredAt, in: ...Date.now)
                .labelsHidden()
                .tint(Color.brand)
        }
        .card(padding: Spacing.s)
        .disabled(isBusy)
    }
}

#Preview {
    NavigationStack {
        RecognitionResultView(photoId: UUID(), context: .meal) {}
    }
}
