import Foundation

struct ChartPhotoMember: Identifiable {
    let id: String
    let mark: DailyReport.Episode.IntakeMark
}

struct ChartPhotoGroup: Identifiable {
    let members: [ChartPhotoMember]
    let anchorValue: Double?
    var id: String { members[0].id }
    var time: Date { members[0].mark.occurredAt }
    var photoId: UUID { members[0].mark.photoId! }

    private init(members: [ChartPhotoMember], points: [GlucosePoint]) {
        self.members = members
        anchorValue = GlucoseCurve(points: points).anchorValue(at: members[0].mark.occurredAt)
    }

    static func make(marks: [DailyReport.Episode.IntakeMark], day: Date, points: [GlucosePoint]) -> [ChartPhotoGroup] {
        let photos = marks.enumerated().filter {
            $0.element.photoId != nil && ReportDay.calendar.isDate($0.element.occurredAt, inSameDayAs: day)
        }.sorted {
            if $0.element.occurredAt == $1.element.occurredAt { return $0.offset < $1.offset }
            return $0.element.occurredAt < $1.element.occurredAt
        }.map {
            ChartPhotoMember(id: "\($0.element.photoId!.uuidString)-\($0.offset)", mark: $0.element)
        }
        var batches: [[ChartPhotoMember]] = []
        for photo in photos {
            if let last = batches.indices.last,
               photo.mark.occurredAt.timeIntervalSince(batches[last][0].mark.occurredAt) <= 30 * 60 {
                batches[last].append(photo)
            } else { batches.append([photo]) }
        }
        return batches.map { ChartPhotoGroup(members: $0, points: points) }
    }
}
