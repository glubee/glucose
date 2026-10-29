//
//  RecordDetailView.swift
//  glucose
//
//  기록 상세(v5). 사실만 보여준다: 무엇을 먹었는지, 인슐린을 얼마나 맞았는지. 용량 조언은 하지 않는다.
//

import SwiftUI

struct RecordDetailView: View {
    let item: RecordItem
    var allowsEditing = true
    var onChanged: () async -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var showEditInsulin = false
    @State private var showEditFood = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                header

                switch item {
                case .intake(let record):
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader(title: "먹은 음식", trailing: "\(record.items.count)가지")
                        ForEach(record.items) { food in
                            HStack {
                                Text(food.name)
                                    .font(.body1)
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                if let quantity = food.displayQuantity {
                                    Text(quantity)
                                        .font(.body2.weight(.semibold))
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                            if food.id != record.items.last?.id { Divider().overlay(Color.line) }
                        }
                    }
                    .card()

                    Button("기록 고치기") { showEditFood = true }
                        .buttonStyle(.glubeeSecondary)
                        .disabled(!allowsEditing)
                case .insulin(let record):
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader(title: "인슐린 기록")
                        LabeledContent("단위", value: "\(record.units.formattedUnits)단위")
                        LabeledContent("종류", value: record.kind)
                    }
                    .font(.body1)
                    .foregroundStyle(Color.textPrimary)
                    .card(.insulin)

                    Button("기록 고치기") { showEditInsulin = true }
                        .buttonStyle(.glubeeSecondary)
                        .disabled(!allowsEditing)
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.m)
        }
        .background(Color.canvas)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditInsulin) {
            if case .insulin(let record) = item {
                InsulinRecordFormView(
                    mode: .edit(id: record.id),
                    occurredAt: record.occurredAt,
                    units: record.units,
                    kind: record.kind,
                    onSaved: {
                        RecordChanges.shared.publish(.updated)
                        Task { await onChanged(); dismiss() }
                    },
                    onDeleted: {
                        RecordChanges.shared.publish(.deleted)
                        Task { await onChanged(); dismiss() }
                    }
                )
            }
        }
        .sheet(isPresented: $showEditFood) {
            if case .intake(let record) = item {
                FoodRecordFormView(record: record,
                                   onSaved: { Task { await onChanged(); dismiss() } },
                                   onDeleted: { Task { await onChanged(); dismiss() } })
            }
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .background(fill, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(navigationTitle)
                    .font(.headline1)
                    .foregroundStyle(Color.textPrimary)
                Text("\(ReportDay.displayString(from: item.occurredAt)) \(ReportDay.timeString(from: item.occurredAt))")
                    .font(.body2)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var navigationTitle: String {
        switch item {
        case .intake(let record): record.context.displayName
        case .insulin: "인슐린"
        }
    }

    private var icon: String {
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
}

#Preview {
    NavigationStack {
        RecordDetailView(item: .intake(IntakeRecord(
            id: UUID(), occurredAt: .now, context: .meal,
            items: [FoodItem(id: UUID(), name: "현미밥", count: 1, unit: "공기")]
        )))
    }
}
