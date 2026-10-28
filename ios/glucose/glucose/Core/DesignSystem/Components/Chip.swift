//
//  Chip.swift
//  glucose
//
//  선택 칩(기록 상황, 필터, 단위). 선택되면 연노랑 바탕 + 체크.
//

import SwiftUI

struct Chip: View {
    let title: String
    let isSelected: Bool
    /// 저혈당·고혈당 필터 앞의 작은 점
    var dot: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xxs) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                } else if let dot {
                    Circle().fill(dot).frame(width: 6, height: 6)
                }
                Text(title)
                    .font(.body2.weight(isSelected ? .semibold : .regular))
            }
            // 선택 바탕은 연노랑(다크에선 어두운 노랑)이라 onBrand가 아니라 textPrimary를 쓴다
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, Spacing.s)
            .frame(minHeight: 36)
            .background(isSelected ? Color.brandSofter : Color.canvas, in: Capsule())
            .overlay {
                if !isSelected {
                    Capsule().strokeBorder(Color.line, lineWidth: 1)
                }
            }
            .frame(minHeight: Metrics.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 여러 칩 중 하나를 고르는 줄. 넘치면 가로 스크롤
struct ChipPicker<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(options, id: \.value) { option in
                    Chip(title: option.title, isSelected: selection == option.value) {
                        selection = option.value
                    }
                }
            }
        }
    }
}

#if DEBUG
struct ChipSamples: View {
    @State private var context = "SNACK"

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            ChipPicker(
                options: [("MEAL", "식사"), ("SNACK", "간식"), ("HYPO_TREATMENT", "저혈당 대응"), ("ALCOHOL", "술")],
                selection: $context
            )
            HStack {
                Chip(title: "전체", isSelected: true) {}
                Chip(title: "저혈당", isSelected: false, dot: .mintStrong) {}
                Chip(title: "고혈당", isSelected: false, dot: .alert) {}
            }
        }
    }
}

#Preview {
    ChipSamples().padding(Spacing.gutter)
}
#endif
