//
//  InsulinRecordFormViewModel.swift
//  glucose
//
//  입력만 받는다. 단위·시각·종류를 기록할 뿐, 용량을 추천하거나 판단하지 않는다.
//

import Foundation

@MainActor
@Observable
final class InsulinRecordFormViewModel {

    enum Mode: Equatable {
        case create
        case edit(id: UUID)
    }

    private let service: InsulinServing
    private let changes: RecordChanges
    let mode: Mode
    var occurredAt: Date
    var units: Double?
    var kind: String

    private(set) var isSaving = false
    private var hasCompleted = false
    private(set) var isDeleting = false
    private(set) var errorMessage: String?

    init(mode: Mode = .create, occurredAt: Date = .now, units: Double? = nil, kind: String = "",
         service: InsulinServing? = nil, changes: RecordChanges? = nil) {
        self.service = service ?? RecordDataSource.insulinService
        self.changes = changes ?? .shared
        self.mode = mode
        self.occurredAt = occurredAt
        self.units = units
        self.kind = kind
    }

    var isSaveEnabled: Bool {
        guard let units, units > 0 else { return false }
        return !kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving && !isDeleting && !hasCompleted
    }

    func save() async -> Bool {
        guard isSaveEnabled, let units else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let request = InsulinEventRequest(occurredAt: occurredAt, units: units, kind: kind)
        do {
            let response: InsulinEventResponse
            switch mode {
            case .create: response = try await service.create(request)
            case .edit(let id): response = try await service.update(id: id, request: request)
            }
            hasCompleted = true
            changes.publish(mode == .create ? .created : .updated, recordID: response.id)
            return true
        } catch {
            errorMessage = "저장하지 못했어요. 다시 시도해 주세요."
            return false
        }
    }

    func delete() async -> Bool {
        guard case .edit(let id) = mode, !isSaving, !isDeleting, !hasCompleted else { return false }
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }

        do {
            try await service.delete(id: id)
            hasCompleted = true
            changes.publish(.deleted, recordID: id)
            return true
        } catch {
            errorMessage = "지우지 못했어요. 다시 시도해 주세요."
            return false
        }
    }
}
