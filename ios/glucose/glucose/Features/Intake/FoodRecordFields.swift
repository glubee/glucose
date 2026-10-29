import SwiftUI

/// 음식 확인·글로 남기기·기록 고치기에서 같은 입력 필드를 사용한다.
struct FoodRecordFields: View {
    @Binding var draft: FoodRecordDraft

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                SectionHeader(title: "어떤 기록인가요?")
                ChipPicker(options: [(.meal, "식사"), (.snack, "간식"),
                                     (.hypoTreatment, "저혈당 대응"), (.alcohol, "술")],
                           selection: $draft.context)
            }

            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "먹은 음식", subtitle: "이름과 양을 확인해 주세요. 모르는 개수나 단위는 비워둘 수 있어요.")
                ForEach($draft.items) { $item in
                    FoodItemEditor(item: $item) {
                        draft.items.removeAll { $0.id == item.id }
                    }
                }
                Button { draft.items.append(.blank()) } label: {
                    Label("음식 추가", systemImage: "plus")
                }
                .buttonStyle(.glubeeSecondary)
                if !draft.items.isEmpty && !draft.isValid {
                    Text("음식 이름과 개수를 확인해 주세요.")
                        .font(.caption1)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "언제 먹었나요?")
                DatePicker("먹은 시각", selection: $draft.occurredAt, in: ...Date.now)
                    .font(.body2)
                    .tint(Color.textPrimary)
                    .card(padding: Spacing.s)
            }
        }
    }
}

private struct FoodItemEditor: View {
    @Binding var item: EditableFoodItem
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.s) {
                TextField("음식 이름", text: $item.name)
                    .font(.body1)
                    .accessibilityLabel("음식 이름")
                    .submitLabel(.done)
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: Metrics.minTapTarget, height: Metrics.minTapTarget)
                }
                .accessibilityLabel(item.name.isEmpty ? "이 음식 지우기" : "\(item.name) 지우기")
            }
            HStack(spacing: Spacing.xs) {
                quantityButton("minus", label: "개수 줄이기", disabled: (item.count ?? 0) <= 1) {
                    if let count = item.count { item.count = count - 1 }
                }
                TextField("개수", value: $item.count, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.body2.monospacedDigit())
                    .frame(minWidth: 44)
                    .accessibilityLabel("개수")
                quantityButton("plus", label: "개수 늘리기", disabled: (item.count ?? 0) >= FoodRecordDraft.maximumCount) {
                    item.count = max(1, (item.count ?? 0) + 1)
                }
                TextField("단위 (개·잔 등)", text: $item.unit)
                    .font(.body2)
                    .accessibilityLabel("단위")
                    .padding(.horizontal, Spacing.xs)
                    .frame(minHeight: Metrics.minTapTarget)
                    .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.field))
            }
        }
        .foregroundStyle(Color.textPrimary)
        .card(padding: Spacing.s)
    }

    private func quantityButton(_ icon: String, label: String, disabled: Bool,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .frame(width: Metrics.minTapTarget, height: Metrics.minTapTarget)
                .background(Color.surfaceMuted, in: Circle())
        }
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}
