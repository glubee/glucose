//
//  InsulinConfirmView.swift
//  glucose
//
//  위젯·홈에서 여는 인슐린 투여 확인. 제품·단위는 사용자가 직접 넣은 "평소 인슐린"으로만
//  미리 채우고, 시각은 지금. "투여 확인" 한 번이면 저장된다(docs/ios-design-v4.md 0장).
//  앱은 용량을 계산하거나 추천하지 않는다.
//

import SwiftUI

struct InsulinConfirmView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: InsulinRecordFormViewModel
    @State private var selectedInsulinId: UUID?
    @State private var unitsText: String
    @State private var editsTime = false
    /// 평소 인슐린이 없을 때, 입력한 값을 다음에도 채울지
    @State private var rememberAsUsual: Bool
    @State private var saved = false
    @FocusState private var unitsFocused: Bool

    private let preferences: UserPreferences
    private let onSaved: () -> Void

    init(preferences: UserPreferences = .shared, onSaved: @escaping () -> Void = {}) {
        self.preferences = preferences
        self.onSaved = onSaved
        let first = preferences.usualInsulins.first
        _viewModel = State(initialValue: InsulinRecordFormViewModel(units: first?.units, kind: first?.name ?? ""))
        _selectedInsulinId = State(initialValue: first?.id)
        _unitsText = State(initialValue: first?.units.map(Self.format) ?? "")
        _rememberAsUsual = State(initialValue: preferences.usualInsulins.isEmpty)
    }

    private var usualInsulins: [UsualInsulin] { preferences.usualInsulins }

    /// 지금 칸의 값이 고른 평소 인슐린 값 그대로인지
    private var isPrefilled: Bool {
        guard let selected = usualInsulins.first(where: { $0.id == selectedInsulinId }) else { return false }
        return selected.name == viewModel.kind && selected.units == viewModel.units && selected.units != nil
    }

    var body: some View {
        if saved {
            savedView
        } else {
            form
        }
    }

    // MARK: - 입력

    private var form: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            SheetHeader(title: "인슐린 투여 확인", subtitle: "투여한 내용과 시각을 확인해주세요.", onClose: { dismiss() })

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if usualInsulins.count > 1 {
                        ChipPicker(
                            options: usualInsulins.map { ($0.id, $0.name) },
                            selection: Binding(
                                get: { selectedInsulinId ?? usualInsulins[0].id },
                                set: select
                            )
                        )
                    }

                    field("제품") {
                        TextField("예: 초속효성 인슐린", text: $viewModel.kind)
                    }

                    field("투여량") {
                        HStack {
                            TextField("단위", text: $unitsText)
                                .keyboardType(.decimalPad)
                                .focused($unitsFocused)
                                .onChange(of: unitsText) { _, text in
                                    viewModel.units = Double(text.replacingOccurrences(of: ",", with: "."))
                                }
                            Text("U").foregroundStyle(Color.textSecondary)
                        }
                    }

                    if isPrefilled {
                        Label("내가 입력한 평소 값이에요. 다르면 고쳐주세요.", systemImage: "info.circle")
                            .font(.caption1)
                            .foregroundStyle(Color.textSecondary)
                    }

                    timeSection

                    if usualInsulins.isEmpty {
                        Toggle("다음에도 이 값으로 채우기", isOn: $rememberAsUsual)
                            .font(.body2)
                            .tint(Color.mintStrong)
                    }

                    if let message = viewModel.errorMessage {
                        Text(message).font(.caption1).foregroundStyle(Color.alert)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)

            Button {
                Task { await save() }
            } label: {
                if viewModel.isSaving { ProgressView().tint(Color.onBrand) } else { Text("투여 확인") }
            }
            .buttonStyle(.glubeePrimary)
            .disabled(!viewModel.isSaveEnabled || viewModel.isSaving)
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.top, Spacing.l)
        .padding(.bottom, Spacing.s)
        .background(Color.canvas)
        .onAppear {
            // 평소 단위가 없으면 바로 숫자를 칠 수 있게
            if unitsText.isEmpty && !viewModel.kind.isEmpty { unitsFocused = true }
        }
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("실제 투여 시각").font(.body2).foregroundStyle(Color.textSecondary)
            if editsTime {
                DatePicker("실제 투여 시각", selection: $viewModel.occurredAt, in: ...Date.now)
                    .labelsHidden()
            } else {
                HStack {
                    Text("지금 · \(viewModel.occurredAt.formatted(date: .omitted, time: .shortened))")
                        .font(.body1)
                    Spacer()
                    Button("시간 변경") { editsTime = true }
                        .font(.body2)
                        .frame(minHeight: Metrics.minTapTarget)
                }
                .padding(.horizontal, Spacing.m)
                .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.field))
            }
            Text("기록하는 시각이 아니라 실제로 투여한 시각이에요.")
                .font(.caption1)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).font(.body2).foregroundStyle(Color.textSecondary)
            content()
                .font(.body1)
                .padding(.horizontal, Spacing.m)
                .frame(minHeight: Metrics.buttonHeight)
                .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.field))
        }
    }

    // MARK: - 저장 후

    private var savedView: some View {
        VStack(spacing: Spacing.m) {
            Spacer()
            MascotView(pose: .thumbsup, size: 160)
            Text("기록했어요.")
                .font(.headline1)
                .foregroundStyle(Color.textPrimary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.canvas)
        .sensoryFeedback(.success, trigger: saved)
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            dismiss()
        }
    }

    // MARK: - 동작

    private func select(_ id: UUID) {
        guard let insulin = usualInsulins.first(where: { $0.id == id }) else { return }
        selectedInsulinId = id
        viewModel.kind = insulin.name
        unitsText = insulin.units.map(Self.format) ?? ""
        viewModel.units = insulin.units
    }

    private func save() async {
        guard await viewModel.save() else { return }
        if usualInsulins.isEmpty && rememberAsUsual {
            preferences.usualInsulins = [UsualInsulin(name: viewModel.kind.trimmingCharacters(in: .whitespaces),
                                                      units: viewModel.units)]
        }
        onSaved()
        withAnimation(.spring(duration: 0.35)) { saved = true }
    }

    private static func format(_ units: Double) -> String {
        units.formatted(.number.precision(.fractionLength(0...1)))
    }
}

#Preview {
    InsulinConfirmView()
}
