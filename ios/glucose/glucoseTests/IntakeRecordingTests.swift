import XCTest
@testable import glucose

@MainActor
final class IntakeRecordingTests: XCTestCase {
    private let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    func testRecognitionRejectsNewlineOnlyName() {
        let model = RecognitionResultViewModel(photoId: UUID(), context: .meal)
        model.addBlankItem()
        model.updateItem(id: model.items[0].id, name: "\n")
        XCTAssertFalse(model.isSaveEnabled)
    }

    func testDraftValidatesAllNamesAndPositiveCounts() {
        var draft = FoodRecordDraft(items: [.blank()])
        XCTAssertFalse(draft.isValid)
        draft.items[0].name = "밥"
        draft.items[0].count = 0
        XCTAssertFalse(draft.isValid)
        draft.items[0].count = 1
        XCTAssertTrue(draft.isValid)
        draft.items.append(.blank())
        XCTAssertFalse(draft.isValid)
    }

    func testDraftRejectsCountsOutsideServerIntegerRange() {
        var draft = FoodRecordDraft(items: [EditableFoodItem(name: "밥", count: 2_147_483_648,
                                                            unit: "공기", categoryHint: nil, tags: [])])
        XCTAssertFalse(draft.isValid)
        draft.items[0].count = 2_147_483_647
        XCTAssertTrue(draft.isValid)
    }

    func testDraftPreservesUnknownQuantityInsteadOfInventingOne() {
        let response = sample(count: nil, unit: nil)
        let draft = FoodRecordDraft(record: response.toRecord())
        XCTAssertTrue(draft.isValid)
        XCTAssertNil(draft.request.items[0].count)
        XCTAssertNil(draft.request.items[0].unit)
    }

    func testResponseMappingPreservesPhotoAndUserClassification() {
        let response = sample()
        let record = response.toRecord()
        XCTAssertEqual(record.photoId, response.photoId)
        XCTAssertEqual(record.items[0].categoryHint, "DRINK")
        XCTAssertEqual(record.items[0].tags, ["HIGH_FAT"])
        let draft = FoodRecordDraft(record: record)
        XCTAssertEqual(draft.request.photoId, response.photoId)
        XCTAssertEqual(draft.request.items[0].categoryHint, "DRINK")
        XCTAssertEqual(draft.request.items[0].tags, ["HIGH_FAT"])
    }

    func testManualCreationSendsMultipleFoodsWithoutPhoto() async {
        let service = IntakeServiceDouble(response: sample())
        let changes = RecordChanges()
        let model = FoodRecordFormViewModel(service: service, changes: changes)
        model.draft.context = .snack
        model.draft.occurredAt = timestamp
        model.draft.items = [
            EditableFoodItem(name: " 김밥\n", count: 2, unit: " 줄 ", categoryHint: nil, tags: []),
            EditableFoodItem(name: "우유", count: 1, unit: "잔", categoryHint: nil, tags: [])
        ]
        let saved = await model.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(service.creates.count, 1)
        XCTAssertNil(service.creates[0].photoId)
        XCTAssertEqual(service.creates[0].context, "SNACK")
        XCTAssertEqual(service.creates[0].occurredAt, timestamp)
        XCTAssertEqual(service.creates[0].items.map(\.name), ["김밥", "우유"])
        XCTAssertEqual(service.creates[0].items[0].unit, "줄")
        XCTAssertEqual(changes.revision, 1)
        XCTAssertEqual(changes.lastRecordID, service.response.id)
        let repeated = await model.save()
        XCTAssertFalse(repeated)
        XCTAssertEqual(service.creates.count, 1)
    }

    func testInvalidInputDoesNotCallServer() async {
        let service = IntakeServiceDouble(response: sample())
        let model = FoodRecordFormViewModel(service: service, changes: RecordChanges())
        let saved = await model.save()
        XCTAssertFalse(saved)
        XCTAssertTrue(service.creates.isEmpty)
    }

    func testEditLoadsFullDetailAndPreservesMetadataInReplacement() async {
        let response = sample()
        let service = IntakeServiceDouble(response: response)
        let changes = RecordChanges()
        let model = FoodRecordFormViewModel(record: response.toRecord(), service: service, changes: changes)
        XCTAssertFalse(model.isSaveEnabled)
        await model.load()
        XCTAssertEqual(service.loadedIDs, [response.id])
        model.draft.context = .alcohol
        model.draft.occurredAt = timestamp.addingTimeInterval(-86_400)
        model.draft.items[0].name = "수정한 음식"
        model.draft.items.append(EditableFoodItem(name: "추가한 음식", count: 2, unit: "개", categoryHint: nil, tags: []))
        let saved = await model.save()
        XCTAssertTrue(saved)
        XCTAssertTrue(service.creates.isEmpty)
        XCTAssertEqual(service.updates[0].0, response.id)
        let request = service.updates[0].1
        XCTAssertEqual(request.context, "ALCOHOL")
        XCTAssertEqual(request.photoId, response.photoId)
        XCTAssertEqual(request.occurredAt, timestamp.addingTimeInterval(-86_400))
        XCTAssertEqual(request.items.map(\.name), ["수정한 음식", "추가한 음식"])
        XCTAssertEqual(request.items[0].categoryHint, "DRINK")
        XCTAssertEqual(request.items[0].tags, ["HIGH_FAT"])
        XCTAssertEqual(changes.lastMutation, .updated)
        XCTAssertEqual(changes.revision, 1)
    }

    func testFailedDetailLoadBlocksSavingUntilRetrySucceeds() async {
        let response = sample()
        let service = IntakeServiceDouble(response: response)
        service.shouldFail = true
        let model = FoodRecordFormViewModel(record: response.toRecord(), service: service, changes: RecordChanges())
        await model.load()
        XCTAssertFalse(model.isSaveEnabled)
        XCTAssertNotNil(model.errorMessage)
        let saved = await model.save()
        XCTAssertFalse(saved)
        XCTAssertTrue(service.updates.isEmpty)
        service.shouldFail = false
        await model.load()
        XCTAssertTrue(model.isSaveEnabled)
    }

    func testFailedSaveKeepsInputAndDoesNotPublishChange() async {
        let service = IntakeServiceDouble(response: sample())
        service.shouldFail = true
        let changes = RecordChanges()
        let model = FoodRecordFormViewModel(service: service, changes: changes)
        model.draft.items[0].name = "입력한 음식"
        let saved = await model.save()
        XCTAssertFalse(saved)
        XCTAssertEqual(model.draft.items[0].name, "입력한 음식")
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isSaving)
        XCTAssertEqual(changes.revision, 0)
        service.shouldFail = false
        let retried = await model.save()
        XCTAssertTrue(retried)
        XCTAssertEqual(changes.revision, 1)
    }

    func testConcurrentSaveAndDeleteCannotIssueAnotherMutation() async {
        let response = sample()
        let service = IntakeServiceDouble(response: response)
        let changes = RecordChanges()
        let model = FoodRecordFormViewModel(record: response.toRecord(), service: service, changes: changes)
        await model.load()
        service.suspendSave = true
        let first = Task { await model.save() }
        while service.saveContinuation == nil { await Task.yield() }
        let duplicate = await model.save()
        let deletion = await model.delete()
        XCTAssertFalse(duplicate)
        XCTAssertFalse(deletion)
        XCTAssertEqual(service.updates.count, 1)
        XCTAssertTrue(service.deletedIDs.isEmpty)
        service.saveContinuation?.resume(returning: response)
        let firstSaved = await first.value
        XCTAssertTrue(firstSaved)
        XCTAssertEqual(changes.revision, 1)
    }

    func testDeletePublishesOnlyAfterSuccessfulServerResponse() async {
        let response = sample()
        let service = IntakeServiceDouble(response: response)
        let changes = RecordChanges()
        let model = FoodRecordFormViewModel(record: response.toRecord(), service: service, changes: changes)
        await model.load()
        service.shouldFail = true
        let failed = await model.delete()
        XCTAssertFalse(failed)
        XCTAssertEqual(changes.revision, 0)
        service.shouldFail = false
        let deleted = await model.delete()
        XCTAssertTrue(deleted)
        XCTAssertEqual(service.deletedIDs, [response.id, response.id])
        XCTAssertEqual(changes.lastMutation, .deleted)
        XCTAssertEqual(changes.revision, 1)
        let duplicate = await model.delete()
        XCTAssertFalse(duplicate)
    }

    func testRecognitionCanChangeMealToSnackBeforeConfirming() async {
        let response = sample()
        let service = IntakeServiceDouble(response: response)
        let changes = RecordChanges()
        let photoID = UUID()
        let model = RecognitionResultViewModel(photoId: photoID, context: .meal, occurredAt: timestamp,
                                                service: service, changes: changes)
        await model.loadRecognition()
        model.draft.context = .snack
        let saved = await model.confirm()
        XCTAssertTrue(saved)
        XCTAssertEqual(service.creates[0].context, "SNACK")
        XCTAssertEqual(service.creates[0].photoId, photoID)
        XCTAssertEqual(service.creates[0].occurredAt, timestamp)
        XCTAssertEqual(service.creates[0].items[0].tags, ["HIGH_FAT"])
        XCTAssertEqual(changes.revision, 1)
        let duplicate = await model.confirm()
        XCTAssertEqual(changes.lastRecordID, service.response.id)
        XCTAssertFalse(duplicate)
        XCTAssertEqual(service.creates.count, 1)
    }

    func testRecognitionFailureAllowsManualCorrectionAndKeepsDraftOnSaveFailure() async {
        let service = IntakeServiceDouble(response: sample())
        service.shouldFail = true
        let changes = RecordChanges()
        let model = RecognitionResultViewModel(photoId: UUID(), context: .meal, service: service, changes: changes)
        await model.loadRecognition()
        model.addBlankItem()
        model.updateItem(id: model.items[0].id, name: "직접 적은 음식")
        model.draft.context = .hypoTreatment
        let failed = await model.confirm()
        XCTAssertFalse(failed)
        XCTAssertEqual(model.items[0].name, "직접 적은 음식")
        XCTAssertEqual(model.draft.context, .hypoTreatment)
        XCTAssertEqual(changes.revision, 0)
        service.shouldFail = false
        let retried = await model.confirm()
        XCTAssertTrue(retried)
        XCTAssertEqual(service.creates.last?.context, "HYPO_TREATMENT")
        XCTAssertEqual(changes.revision, 1)
    }

    private func sample(count: Int? = 1, unit: String? = "잔") -> IntakeResponse {
        IntakeResponse(id: UUID(), context: "MEAL", occurredAt: timestamp, photoId: UUID(), items: [
            IntakeItemResponse(id: UUID(), name: "우유", count: count, unit: unit,
                               categoryHint: "DRINK", tags: ["HIGH_FAT"], sugarGrams: nil)
        ], createdAt: timestamp, updatedAt: timestamp)
    }
}

@MainActor
private final class IntakeServiceDouble: IntakeServing {
    let response: IntakeResponse
    var shouldFail = false
    var suspendSave = false
    var saveContinuation: CheckedContinuation<IntakeResponse, Error>?
    var creates: [CreateIntakeRequest] = []
    var updates: [(UUID, CreateIntakeRequest)] = []
    var loadedIDs: [UUID] = []
    var deletedIDs: [UUID] = []

    init(response: IntakeResponse) { self.response = response }

    func get(id: UUID) async throws -> IntakeResponse {
        loadedIDs.append(id)
        if shouldFail { throw URLError(.notConnectedToInternet) }
        return response
    }

    func create(_ request: CreateIntakeRequest) async throws -> IntakeResponse {
        creates.append(request)
        return try await saveResult()
    }

    func update(id: UUID, request: CreateIntakeRequest) async throws -> IntakeResponse {
        updates.append((id, request))
        return try await saveResult()
    }

    func delete(id: UUID) async throws {
        deletedIDs.append(id)
        if shouldFail { throw URLError(.notConnectedToInternet) }
    }

    func recognize(photoId: UUID) async throws -> RecognitionResponse {
        if shouldFail { throw URLError(.notConnectedToInternet) }
        return RecognitionResponse(isFoodPhoto: true, items: [
            RecognizedFoodItem(name: "우유", count: 1, unit: "잔", categoryHint: "DRINK",
                               tags: ["HIGH_FAT"], confidence: "HIGH")
        ], likelyConsumedAll: nil)
    }

    private func saveResult() async throws -> IntakeResponse {
        if shouldFail { throw URLError(.notConnectedToInternet) }
        if suspendSave { return try await withCheckedThrowingContinuation { saveContinuation = $0 } }
        return response
    }
}
