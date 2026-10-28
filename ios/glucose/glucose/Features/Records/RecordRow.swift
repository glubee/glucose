//
//  RecordRow.swift
//  glucose
//
//  전체 기록의 한 줄(v5): 왼쪽 동그란 아이콘(음식 = 노랑, 저혈당 대응 = 민트, 인슐린 = 보라), 시각, 내용.
//

import SwiftUI

struct RecordRow: View {
    let item: RecordItem

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(fill, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline2)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption1)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .accessibilityHidden(true)
        }
        .card(padding: Spacing.s)
        .accessibilityElement(children: .combine)
    }

    private var systemImage: String {
        switch item {
        case .intake(let record): record.context.systemImage
        case .insulin: "syringe"
        }
    }

    private var tint: Color {
        switch item {
        case .intake(let record): record.context == .hypoTreatment ? .mintStrong : .onBrandSoft
        case .insulin: .insulin
        }
    }

    private var fill: Color {
        switch item {
        case .intake(let record): record.context == .hypoTreatment ? .mintSoft : .brandSoft
        case .insulin: .insulinSoft
        }
    }

    private var title: String {
        switch item {
        case .intake(let record): record.summary.isEmpty ? record.context.displayName : record.summary
        case .insulin(let record): "인슐린 \(record.units.formattedUnits)단위"
        }
    }

    private var subtitle: String {
        let time = ReportDay.timeString(from: item.occurredAt)
        return switch item {
        case .intake(let record): "\(time) · \(record.context.displayName)"
        case .insulin(let record): "\(time) · \(record.kind)"
        }
    }
}

extension Double {
    /// 6 → "6", 6.5 → "6.5"
    var formattedUnits: String {
        truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", self)
            : String(format: "%.1f", self)
    }
}

#Preview {
    VStack {
        RecordRow(item: .intake(IntakeRecord(
            id: UUID(), occurredAt: .now, context: .meal,
            items: [FoodItem(id: UUID(), name: "현미밥", count: 1, unit: "공기")]
        )))
        RecordRow(item: .insulin(InsulinRecord(id: UUID(), occurredAt: .now, units: 6, kind: "식사")))
    }
    .padding()
}
