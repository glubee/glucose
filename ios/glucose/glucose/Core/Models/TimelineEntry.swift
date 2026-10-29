import Foundation

enum TimelineEntry: Identifiable {
    case record(RecordItem)
    case pending(PendingPhoto)

    var id: String {
        switch self {
        case .record(let item):
            switch item {
            case .intake: "intake-\(item.id)"
            case .insulin: "insulin-\(item.id)"
            }
        case .pending(let photo): "pending-\(photo.id)"
        }
    }
    var occurredAt: Date {
        switch self {
        case .record(let item): item.occurredAt
        case .pending(let photo): photo.capturedAt
        }
    }
}
