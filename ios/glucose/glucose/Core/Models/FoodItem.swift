//
//  FoodItem.swift
//  glucose
//

import Foundation

struct FoodItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let count: Int?
    let unit: String?
    let categoryHint: String?
    let tags: [String]

    init(id: UUID, name: String, count: Int?, unit: String?, categoryHint: String? = nil, tags: [String] = []) {
        self.id = id
        self.name = name
        self.count = count
        self.unit = unit
        self.categoryHint = categoryHint
        self.tags = tags
    }

    var displayQuantity: String? {
        guard let count, let unit else { return nil }
        return "\(count)\(unit)"
    }
}
