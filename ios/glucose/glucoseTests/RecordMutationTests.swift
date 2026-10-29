import XCTest
@testable import glucose

@MainActor
final class RecordMutationTests: XCTestCase {
    func testInsulinCreatedIDRefreshesConsumersOnlyOnce() async {
        let service = InsulinMutationDouble()
        let changes = RecordChanges()
        let model = InsulinRecordFormViewModel(units: 3, kind: "사용자 입력", service: service, changes: changes)
        let saved = await model.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(changes.lastRecordID, service.id)
        XCTAssertEqual(changes.lastMutation, .created)
        XCTAssertEqual(changes.revision, 1)
        let duplicate = await model.save()
        XCTAssertFalse(duplicate)
        XCTAssertEqual(service.requests.count, 1)
        XCTAssertEqual(service.requests.first?.units, 3)
        XCTAssertEqual(service.requests.first?.kind, "사용자 입력")
    }

    func testInsulinFailureKeepsInputAndPublishesNothingUntilRetrySucceeds() async {
        let service = InsulinMutationDouble()
        service.fail = true
        let changes = RecordChanges()
        let model = InsulinRecordFormViewModel(units: 2.5, kind: "입력값", service: service, changes: changes)
        let failed = await model.save()
        XCTAssertFalse(failed)
        XCTAssertNil(changes.lastRecordID)
        XCTAssertEqual(changes.revision, 0)
        XCTAssertEqual(model.units, 2.5)
        service.fail = false
        let retried = await model.save()
        XCTAssertTrue(retried)
        XCTAssertEqual(changes.revision, 1)
    }

    func testInsulinUpdateAndDeletePublishTheExistingID() async {
        let service = InsulinMutationDouble(), changes = RecordChanges()
        let edit = InsulinRecordFormViewModel(mode: .edit(id: service.id), units: 4, kind: "종류",
                                              service: service, changes: changes)
        let updated = await edit.save()
        XCTAssertTrue(updated)
        XCTAssertEqual(changes.lastMutation, .updated)
        XCTAssertEqual(changes.lastRecordID, service.id)
        let deletion = InsulinRecordFormViewModel(mode: .edit(id: service.id), service: service, changes: changes)
        let deleted = await deletion.delete()
        XCTAssertTrue(deleted)
        XCTAssertEqual(changes.lastMutation, .deleted)
        XCTAssertEqual(changes.lastRecordID, service.id)
        XCTAssertEqual(changes.revision, 2)
    }

    func testOnlyCreatedTodayRecordIsFocusedOnceAndOldDateIsIgnored() async {
        let day = ReportDay.date(fromAPIString: "2026-10-29")!
        let current = RecordItem.intake(IntakeRecord(id: UUID(), occurredAt: day, context: .meal, items: []))
        let repo = TimelineRepositoryDouble(intakes: ["start": .init(items: [current], nextCursor: nil)])
        let model = TodayTimelineViewModel(repository: repo)
        let changes = RecordChanges()
        await model.load(day: day)
        changes.publish(.created, recordID: current.id)
        model.prepareFocus(changes: changes, photos: [])
        let expected = "intake-\(current.id)"
        XCTAssertEqual(model.focusID, expected)
        model.finishFocus(expected)
        model.prepareFocus(changes: changes, photos: [])
        XCTAssertNil(model.focusID)
        changes.publish(.updated, recordID: current.id)
        model.prepareFocus(changes: changes, photos: [])
        XCTAssertNil(model.focusID)
        changes.publish(.created, recordID: UUID())
        model.prepareFocus(changes: changes, photos: [])
        XCTAssertNil(model.focusID)
    }
}

@MainActor
private final class InsulinMutationDouble: InsulinServing {
    let id = UUID()
    var fail = false
    var requests: [InsulinEventRequest] = []
    func create(_ request: InsulinEventRequest) async throws -> InsulinEventResponse {
        requests.append(request); return try result(request)
    }
    func update(id: UUID, request: InsulinEventRequest) async throws -> InsulinEventResponse {
        requests.append(request); return try result(request)
    }
    func delete(id: UUID) async throws { if fail { throw URLError(.notConnectedToInternet) } }
    private func result(_ request: InsulinEventRequest) throws -> InsulinEventResponse {
        if fail { throw URLError(.notConnectedToInternet) }
        return .init(id: id, occurredAt: request.occurredAt, units: request.units, kind: request.kind,
                     createdAt: request.occurredAt, updatedAt: request.occurredAt)
    }
}
