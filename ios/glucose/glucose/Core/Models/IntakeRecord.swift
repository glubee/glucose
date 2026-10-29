//
//  IntakeRecord.swift
//  glucose
//

import Foundation

struct IntakeRecord: Identifiable, Hashable {
    let id: UUID
    let occurredAt: Date
    let context: IntakeContext
    let items: [FoodItem]
    let photoId: UUID?

    init(id: UUID, occurredAt: Date, context: IntakeContext, items: [FoodItem], photoId: UUID? = nil) {
        self.id = id
        self.occurredAt = occurredAt
        self.context = context
        self.items = items
        self.photoId = photoId
    }

    var summary: String {
        items.map(\.name).joined(separator: ", ")
    }
}
