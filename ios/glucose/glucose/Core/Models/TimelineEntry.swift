import Foundation

enum TimelineEntry: Identifiable {
    case record(RecordItem)
    case pending(PendingPhoto)

    var id: String {
        switch self {
        case .record(let item): item.timelineID
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
