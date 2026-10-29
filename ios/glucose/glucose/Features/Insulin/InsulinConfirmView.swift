//
//  InsulinConfirmView.swift
//  glucose
//
//  위젯·홈에서 여는 인슐린 투여 확인. 제품·단위는 사용자가 직접 넣은 "평소 인슐린"으로만
//  미리 채우고, 시각은 지금. "투여 확인" 한 번이면 저장된다(docs/ios-design-v4.md 0장).
//  저장한 뒤 "인슐린 하나 더 기록하기"로 같은 화면에서 이어서 남길 수 있다(식사 + 기저 등).
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
    /// 이 화면에서 연달아 남긴 기록(예: 식사 인슐린 + 기저 인슐린)
    @State private var savedEntries: [String] = []
    @FocusState private var unitsFocused: Bool

    private let preferences: UserPreferences
    private let onSaved: () -> Void

    init(preferences: UserPreferences? = nil, onSaved: @escaping () -> Void = {}) {
        let preferences = preferences ?? RecordDataSource.preferences
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

    /// 평소 값이 채워져 있으면 v5 프로토타입처럼 작은 확인 카드로 보여주고, 카드를 누르면 고치는 화면
    @State private var editing = false

    var body: some View {
        if saved {
            savedView
        } else if isPrefilled && !editing {
            compact
        } else {
            form
        }
    }

    // MARK: - 확인 카드

    private var compact: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("지금 맞을 인슐린")
                .font(.pretendard(15, relativeTo: .subheadline, weight: .semibold))
                .foregroundStyle(Color.textSecondary)

            if usualInsulins.count > 1 {
                ChipPicker(options: usualInsulins.map { ($0.id, $0.name) },
                           selection: Binding(get: { selectedInsulinId ?? usualInsulins[0].id }, set: select))
            }

            Button { withAnimation(.spring(duration: 0.3)) { editing = true } } label: {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(viewModel.kind)
                        .font(.pretendard(20, relativeTo: .title3, weight: .bold))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(unitsText)
                            .font(.pretendard(44, relativeTo: .largeTitle, weight: .heavy))
                            .monospacedDigit()
                        Text("단위").font(.pretendard(17, relativeTo: .headline, weight: .bold))
                    }
                    Text("지금 · \(viewModel.occurredAt.formatted(date: .omitted, time: .shortened))")
                        .font(.pretendard(15, relativeTo: .subheadline, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                }
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.l)
                .background(Color.insulinSoft, in: RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(viewModel.kind) \(unitsText)단위, 지금. 눌러서 고치기")

            Text("내가 입력한 평소 값이에요. 다르면 눌러서 고쳐주세요.")
                .font(.caption1)
                .foregroundStyle(Color.textSecondary)

            if let message = viewModel.errorMessage {
                Text(message).font(.caption1).foregroundStyle(Color.alert)
            }

            Spacer(minLength: 0)

            Button {
                Task { await save() }
            } label: {
                if viewModel.isSaving { ProgressView().tint(Color.onButton) } else { Text("투여 확인") }
            }
            .buttonStyle(.glubeePrimary)
            .disabled(viewModel.isSaving)
            Button("닫기") { dismiss() }
                .font(.pretendard(15, relativeTo: .subheadline, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, minHeight: Metrics.minTapTarget)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.l)
        .padding(.bottom, Spacing.xs)
        .background(Color.canvas)
        .presentationDetents([.medium, .large])
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
        VStack(spacing: Spacing.s) {
            Spacer()
            MascotView(pose: .thumbsup, size: 140, motion: .jump)
            Text("기록했어요")
                .font(.pretendard(24, relativeTo: .title, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            VStack(spacing: Spacing.xxs) {
                ForEach(Array(savedEntries.enumerated()), id: \.offset) { _, entry in
                    Label(entry, systemImage: "syringe")
                        .font(.body2)
                        .foregroundStyle(Color.insulin)
                }
            }
            Spacer()
            Button {
                addAnother()
            } label: {
                Label("인슐린 하나 더 기록하기", systemImage: "plus")
            }
            .buttonStyle(.glubeeSoft)
            .accessibilityIdentifier("insulinAddAnother")
            Button("다 했어요") { dismiss() }
                .buttonStyle(.glubeePrimary)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.s)
        .frame(maxWidth: .infinity)
        .background(Color.canvas)
        .sensoryFeedback(.success, trigger: savedEntries.count)
    }

    /// 저장한 화면을 닫지 않고 새 기록을 이어서 받는다. 한 번 저장한 입력 상태는 다시 저장되지 않으므로 새로 만든다
    private func addAnother() {
        let first = usualInsulins.first
        viewModel = InsulinRecordFormViewModel(units: first?.units, kind: first?.name ?? "")
        selectedInsulinId = first?.id
        unitsText = first?.units.map(Self.format) ?? ""
        editsTime = false
        editing = false
        withAnimation(.spring(duration: 0.3)) { saved = false }
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
        if !RecordDataSource.isPreview { WidgetSnapshot.refresh(noteRecord: true) }
        onSaved()
        let units = viewModel.units.map(Self.format) ?? ""
        savedEntries.append("\(ReportDay.timeString(from: viewModel.occurredAt)) · \(viewModel.kind) \(units)단위")
        withAnimation(.spring(duration: 0.35)) { saved = true }
    }

    private static func format(_ units: Double) -> String {
        units.formatted(.number.precision(.fractionLength(0...1)))
    }
}

#Preview {
    InsulinConfirmView()
}
