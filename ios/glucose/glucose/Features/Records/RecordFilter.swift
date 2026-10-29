import Foundation

enum RecordFilter: String, CaseIterable {
    case all, food, insulin, response
    func includes(_ item: RecordItem) -> Bool {
        switch (self, item) {
        case (.all, _), (.insulin, .insulin): true
        case (.food, .intake(let record)): record.context == .meal || record.context == .snack
        case (.response, .intake(let record)): record.context == .hypoTreatment || record.context == .alcohol
        default: false
        }
    }
    var title: String {
        switch self {
        case .all: "전체"
        case .food: "음식"
        case .insulin: "인슐린"
        case .response: "대응"
        }
    }
}
