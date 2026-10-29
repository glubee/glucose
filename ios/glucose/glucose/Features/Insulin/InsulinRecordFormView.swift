//
//  InsulinRecordFormView.swift
//  glucose
//
//  인슐린 기록 쓰기·고치기(v5). 평소 인슐린은 칩으로 고를 수 있고, 단위는 사용자가 넣은 값 그대로 쓴다(앱이 정하거나 추천하지 않는다).
//

import SwiftUI

struct InsulinRecordFormView: View {
    @State private var viewModel: InsulinRecordFormViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var showTimeEditor = false
    @FocusState private var unitsFocused: Bool

    private let onSaved: () -> Void
    private let onDeleted: () -> Void
    private let usualNames = RecordDataSource.preferences.usualInsulins.map(\.name)

    init(
        mode: InsulinRecordFormViewModel.Mode = .create,
        occurredAt: Date = .now,
        units: Double? = nil,
        kind: String = "",
        onSaved: @escaping () -> Void,
        onDeleted: @escaping () -> Void = {}
    ) {
        _viewModel = State(initialValue: InsulinRecordFormViewModel(mode: mode, occurredAt: occurredAt, units: units, kind: kind))
        self.onSaved = onSaved
        self.onDeleted = onDeleted
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.l) {
                        timeSection
                        unitsSection
                        kindSection
                        if let errorMessage = viewModel.errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.circle")
                                .font(.body2)
                                .foregroundStyle(Color.alert)
                        }
                        if case .edit = viewModel.mode {
                            Button("이 기록 지우기", role: .destructive) { showDeleteConfirm = true }
                                .font(.body2.weight(.semibold))
                                .foregroundStyle(Color.alert)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.vertical, Spacing.m)
                }
                .scrollDismissesKeyboard(.interactively)

                Button {
                    save()
                } label: {
                    if viewModel.isSaving { ProgressView().tint(Color.onButton) } else { Text("저장하기") }
                }
                .buttonStyle(viewModel.isSaveEnabled ? .glubeePrimary : .glubeeMuted)
                .disabled(!viewModel.isSaveEnabled || viewModel.isSaving || viewModel.isDeleting)
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.s)
            }
            .background(Color.canvas)
            .navigationTitle(viewModel.mode == .create ? "인슐린 기록" : "인슐린 기록 고치기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .confirmationDialog("이 기록을 지울까요?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("지우기", role: .destructive) {
                    Task {
                        if await viewModel.delete() {
                            onDeleted()
                            dismiss()
                        }
                    }
                }
                Button("취소", role: .cancel) {}
            }
            .disabled(viewModel.isSaving || viewModel.isDeleting)
        }
    }

    // MARK: - 시각

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "언제 맞았나요?")
            if viewModel.mode == .create && !showTimeEditor {
                HStack {
                    Label("지금", systemImage: "clock")
                        .font(.body1)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Button("시간 바꾸기") { showTimeEditor = true }
                        .font(.body2.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                }
                .card(padding: Spacing.s)
            } else {
                HStack {
                    Label("맞은 시각", systemImage: "clock")
                        .font(.body1)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    DatePicker("맞은 시각", selection: $viewModel.occurredAt, in: ...Date.now)
                        .labelsHidden()
                        .tint(Color.brand)
                }
                .card(padding: Spacing.s)
            }
        }
    }

    // MARK: - 단위

    private var unitsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "몇 단위였나요?")
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                TextField("0", value: $viewModel.units, format: .number)
                    .keyboardType(.decimalPad)
                    .focused($unitsFocused)
                    .font(.bigNumber)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize()
                Text("단위")
                    .font(.headline2)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
            }
            .card(padding: Spacing.s)
            .contentShape(Rectangle())
            .onTapGesture { unitsFocused = true }
        }
    }

    // MARK: - 종류

    private var kindSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "어떤 인슐린인가요?")
            if !usualNames.isEmpty {
                ChipPicker(options: usualNames.map { ($0, $0) }, selection: $viewModel.kind)
            }
            TextField("직접 적기 (예: 식사, 기저)", text: $viewModel.kind)
                .font(.body1)
                .foregroundStyle(Color.textPrimary)
                .padding(Spacing.s)
                .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.field))
        }
    }

    private func save() {
        if viewModel.mode == .create && !showTimeEditor {
            viewModel.occurredAt = .now
        }
        Task {
            if await viewModel.save() {
                onSaved()
                dismiss()
            }
        }
    }
}

#Preview {
    InsulinRecordFormView(onSaved: {})
}
