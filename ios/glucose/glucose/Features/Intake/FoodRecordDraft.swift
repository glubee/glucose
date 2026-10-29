import Foundation

/// 촬영 확인·직접 입력·기존 기록 편집이 함께 사용하는 입력값.
struct FoodRecordDraft {
    static let maximumCount = Int(Int32.max)
    var context: IntakeContext
    var occurredAt: Date
    var photoId: UUID?
    var items: [EditableFoodItem]

    init(context: IntakeContext = .meal, occurredAt: Date = .now, photoId: UUID? = nil,
         items: [EditableFoodItem] = [.blank()]) {
        self.context = context
        self.occurredAt = occurredAt
        self.photoId = photoId
        self.items = items
    }

    init(record: IntakeRecord) {
        self.init(context: record.context, occurredAt: record.occurredAt, photoId: record.photoId,
                  items: record.items.map {
            EditableFoodItem(name: $0.name, count: $0.count, unit: $0.unit ?? "",
                             categoryHint: $0.categoryHint, tags: $0.tags)
        })
    }

    var isValid: Bool {
        !items.isEmpty && items.allSatisfy {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && ($0.count.map { $0 > 0 && $0 <= Self.maximumCount } ?? true)
        }
    }

    var request: CreateIntakeRequest {
        CreateIntakeRequest(context: context.rawValue, occurredAt: occurredAt, photoId: photoId,
                            items: items.map { $0.toRequest() })
    }
}
