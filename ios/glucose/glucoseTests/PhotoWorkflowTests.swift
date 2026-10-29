import XCTest
import UIKit
@testable import glucose

@MainActor
final class PhotoWorkflowTests: XCTestCase {
    func testFailedDeletionPreservesOriginalPhotoBytes() throws {
        let directory = temporaryDirectory()
        let (store, _, _) = makeStore(directory: directory)
        let photo = try XCTUnwrap(store.add(imageData: Data([1, 2, 3]), context: .meal))
        let index = directory.appendingPathComponent("index.json")
        try FileManager.default.removeItem(at: index)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
        XCTAssertFalse(store.remove(photo.id))
        XCTAssertEqual(store.photos.map(\.id), [photo.id])
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: photo)), Data([1, 2, 3]))
    }

    func testFailedRetakeCancelsExistingAutoCloseTimer() async throws {
        let directory = temporaryDirectory()
        let (store, _, _) = makeStore(directory: directory)
        let model = QuickCaptureViewModel(store: store)
        model.capture(image())
        let timer = Task { await model.waitForAutoClose(after: .milliseconds(30)) }
        await Task.yield()
        let index = directory.appendingPathComponent("index.json")
        try FileManager.default.removeItem(at: index)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
        XCTAssertFalse(model.retake())
        let shouldClose = await timer.value
        XCTAssertFalse(shouldClose)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNotNil(model.captured)
    }

    func testConfirmedRecordCannotBeResubmittedAfterCleanupFailureOrRestart() async throws {
        let directory = temporaryDirectory()
        let (store, _, auth) = makeStore(directory: directory)
        let photo = try XCTUnwrap(store.add(imageData: Data([1, 2, 3]), context: .meal))
        auth.value = true
        await store.uploadPending()
        let index = directory.appendingPathComponent("index.json")
        let oldIndex = try Data(contentsOf: index)
        try FileManager.default.removeItem(at: index)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
        XCTAssertFalse(store.finishConfirmation(photo.id))
        XCTAssertTrue(try XCTUnwrap(store.photos.first).hasConfirmedRecord)
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: photo)), Data([1, 2, 3]))
        try FileManager.default.removeItem(at: index)
        try oldIndex.write(to: index)
        let reloaded = makeStore(directory: directory).0
        XCTAssertTrue(try XCTUnwrap(reloaded.photos.first).hasConfirmedRecord,
                      "완료 표시가 index 정리 실패와 앱 재시작을 넘어 남아야 한다")
        XCTAssertTrue(reloaded.finishConfirmation(photo.id))
        XCTAssertTrue(reloaded.photos.isEmpty)
    }

    func testStagedDeletionIsRestoredWhenIndexStillContainsPhoto() throws {
        let directory = temporaryDirectory()
        let (store, _, _) = makeStore(directory: directory)
        let photo = try XCTUnwrap(store.add(imageData: Data([1, 2, 3]), context: .meal))
        let trash = directory.appendingPathComponent(".discarded")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: store.imageURL(for: photo), to: trash.appendingPathComponent(photo.fileName))
        let reloaded = makeStore(directory: directory).0
        XCTAssertEqual(reloaded.photos.map(\.id), [photo.id])
        XCTAssertEqual(try Data(contentsOf: reloaded.imageURL(for: photo)), Data([1, 2, 3]))
    }

    func testLateAlbumSelectionCannotReplacePhotoAfterUploadStarts() {
        let model = PhotoCaptureViewModel()
        model.process(image())
        let original = model.processedData
        let lateSelection = model.beginSelection()
        model.invalidateSelection()
        XCTAssertFalse(model.process(image(), selectionID: lateSelection))
        XCTAssertEqual(model.processedData, original)
    }

    func testOnlyNewestAlbumSelectionCanBeApplied() {
        let model = PhotoCaptureViewModel()
        let first = model.beginSelection()
        let second = model.beginSelection()
        XCTAssertTrue(model.process(image(), selectionID: second))
        let selected = model.processedData
        XCTAssertFalse(model.process(image(), selectionID: first))
        XCTAssertEqual(model.processedData, selected)
    }

    func testDirectPhotoUploadRetryKeepsCheckpointAndNewPhotoResetsIt() async {
        let transport = PhotoTransportDouble()
        transport.failCompletionOnce = true
        let model = PhotoUploadViewModel(uploader: PhotoUploader(transport: transport))
        await model.upload(imageData: Data([1]), context: .meal)
        await model.upload(imageData: Data([1]), context: .meal)
        XCTAssertEqual(model.state, .done)
        XCTAssertEqual(transport.starts, 1)
        XCTAssertEqual(transport.puts, 1)
        model.reset()
        await model.upload(imageData: Data([2]), context: .snack)
        XCTAssertEqual(transport.starts, 2)
        XCTAssertEqual(transport.puts, 2)
    }

    func testLegacyPendingPhotoIndexStillLoads() throws {
        let directory = temporaryDirectory()
        let id = UUID()
        let photo = PendingPhoto(id: id, capturedAt: .now, context: .snack)
        let data = try JSONEncoder().encode([photo])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        json[0].removeValue(forKey: "uploadCheckpoint")
        try JSONSerialization.data(withJSONObject: json).write(to: directory.appendingPathComponent("index.json"))
        let store = makeStore(directory: directory).0
        XCTAssertEqual(store.photos.map(\.id), [id])
        XCTAssertNil(store.photos[0].uploadCheckpoint)
    }

    func testMissingFileBecomesFailureInsteadOfWaitingForever() async throws {
        let (store, uploader, auth) = makeStore()
        let photo = try XCTUnwrap(store.add(imageData: Data([1]), context: .meal))
        try FileManager.default.removeItem(at: store.imageURL(for: photo))
        auth.value = true
        await store.uploadPending()
        XCTAssertEqual(store.status(for: store.photos[0]), .failed)
        XCTAssertNotNil(store.photos[0].uploadErrorMessage)
        XCTAssertEqual(uploader.calls, 0)
    }

    func testOnlyActivePhotoShowsUploadingAndRepeatedRetryIsIgnored() async throws {
        let (store, uploader, auth) = makeStore()
        uploader.suspendFirst = true
        let first = try XCTUnwrap(store.add(imageData: Data([1]), context: .meal))
        let second = try XCTUnwrap(store.add(imageData: Data([2]), context: .snack))
        auth.value = true
        let worker = Task { await store.uploadPending() }
        while uploader.continuation == nil { await Task.yield() }
        XCTAssertEqual(store.activeUploadID, first.id)
        XCTAssertEqual(store.status(for: store.photos.first { $0.id == first.id }!), .uploading)
        XCTAssertEqual(store.status(for: store.photos.first { $0.id == second.id }!), .waiting)
        await store.uploadPending()
        XCTAssertEqual(uploader.calls, 1)
        uploader.continuation?.resume(returning: uploader.serverID)
        await worker.value
        XCTAssertEqual(uploader.calls, 2)
        XCTAssertTrue(store.photos.allSatisfy { store.status(for: $0) == .ready })
        XCTAssertFalse(store.isUploading)
    }

    func testDeletingActivePhotoCannotRestoreItFromLateResponse() async throws {
        let (store, uploader, auth) = makeStore()
        uploader.suspendFirst = true
        let photo = try XCTUnwrap(store.add(imageData: Data([1]), context: .meal))
        auth.value = true
        let worker = Task { await store.uploadPending() }
        while uploader.continuation == nil { await Task.yield() }
        XCTAssertTrue(store.remove(photo.id))
        uploader.continuation?.resume(returning: uploader.serverID)
        await worker.value
        XCTAssertTrue(store.photos.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.imageURL(for: photo).path))
        XCTAssertFalse(store.isUploading)
    }

    func testPhotoAddedDuringUploadIsIncludedInSameQueue() async throws {
        let (store, uploader, auth) = makeStore()
        uploader.suspendFirst = true
        _ = try XCTUnwrap(store.add(imageData: Data([1]), context: .meal))
        auth.value = true
        let worker = Task { await store.uploadPending() }
        while uploader.continuation == nil { await Task.yield() }
        _ = try XCTUnwrap(store.add(imageData: Data([2]), context: .snack))
        uploader.continuation?.resume(returning: uploader.serverID)
        await worker.value
        XCTAssertEqual(uploader.calls, 2)
        XCTAssertEqual(store.photos.filter { $0.photoId != nil }.count, 2)
    }

    func testFailedUploadCheckpointSurvivesAppRestart() async throws {
        let directory = temporaryDirectory()
        let (store, uploader, auth) = makeStore(directory: directory)
        uploader.shouldFail = true
        _ = try XCTUnwrap(store.add(imageData: Data([1]), context: .meal))
        auth.value = true
        await store.uploadPending()
        XCTAssertEqual(store.status(for: store.photos[0]), .failed)
        XCTAssertEqual(store.photos[0].uploadCheckpoint?.photoId, uploader.serverID)
        let (reloaded, retryUploader, retryAuth) = makeStore(directory: directory)
        retryAuth.value = true
        await reloaded.uploadPending()
        XCTAssertEqual((retryUploader.receivedCheckpoints.first ?? nil)?.photoId, uploader.serverID)
        XCTAssertEqual(reloaded.status(for: reloaded.photos[0]), .ready)
    }

    func testRemoveAllInvalidatesOldQueueBeforeNewPhotosAreAdded() async throws {
        let (store, uploader, auth) = makeStore()
        uploader.suspendFirst = true
        _ = try XCTUnwrap(store.add(imageData: Data([1]), context: .meal))
        auth.value = true
        let oldWorker = Task { await store.uploadPending() }
        while uploader.continuation == nil { await Task.yield() }
        store.removeAll()
        let newPhoto = try XCTUnwrap(store.add(imageData: Data([2]), context: .snack))
        await store.uploadPending()
        uploader.continuation?.resume(returning: uploader.serverID)
        await oldWorker.value
        XCTAssertEqual(store.photos.map(\.id), [newPhoto.id])
        XCTAssertEqual(store.status(for: store.photos[0]), .ready)
        XCTAssertFalse(store.isUploading)
    }

    func testCompletionRetryReusesUploadedPhotoWithoutAnotherPut() async throws {
        let transport = PhotoTransportDouble()
        transport.failCompletionOnce = true
        let uploader = PhotoUploader(transport: transport)
        var checkpoint: PhotoUploadCheckpoint?
        do {
            _ = try await uploader.upload(imageData: Data([1]), context: .meal, checkpoint: nil) { checkpoint = $0 }
            XCTFail("완료 응답 실패를 재현해야 한다")
        } catch {}
        XCTAssertTrue(try XCTUnwrap(checkpoint).didUpload)
        let result = try await uploader.upload(imageData: Data([1]), context: .meal, checkpoint: checkpoint) { checkpoint = $0 }
        XCTAssertEqual(result, transport.photoID)
        XCTAssertEqual(transport.starts, 1)
        XCTAssertEqual(transport.puts, 1)
        XCTAssertEqual(transport.completionIDs, [transport.photoID, transport.photoID])
    }

    func testLostPutResponseChecksServerBeforeUploadingAgain() async throws {
        let transport = PhotoTransportDouble()
        transport.losePutResponse = true
        let uploader = PhotoUploader(transport: transport)
        var checkpoint: PhotoUploadCheckpoint?
        do {
            _ = try await uploader.upload(imageData: Data([1]), context: .meal, checkpoint: nil) { checkpoint = $0 }
            XCTFail("PUT 응답 실패를 재현해야 한다")
        } catch {}
        let result = try await uploader.upload(imageData: Data([1]), context: .meal, checkpoint: checkpoint) { checkpoint = $0 }
        XCTAssertEqual(result, transport.photoID)
        XCTAssertEqual(transport.starts, 1)
        XCTAssertEqual(transport.puts, 1)
    }

    func testExpiredTicketWithUploadedBytesStillCompletesSamePhoto() async throws {
        let transport = PhotoTransportDouble()
        transport.hasBytes = true
        let checkpoint = PhotoUploadCheckpoint(photoId: transport.photoID,
            uploadURL: URL(string: "https://example.invalid/upload")!, expiresAt: .distantPast, didUpload: true)
        let result = try await PhotoUploader(transport: transport).upload(imageData: Data([1]), context: .meal,
                                                                          checkpoint: checkpoint) { _ in }
        XCTAssertEqual(result, transport.photoID)
        XCTAssertEqual(transport.starts, 0)
        XCTAssertEqual(transport.puts, 0)
    }

    func testRetakeRemovesOldPendingPhotoAndInvalidatesCloseTimer() async throws {
        let (store, _, _) = makeStore()
        let model = QuickCaptureViewModel(store: store)
        model.capture(image())
        let oldPhoto = try XCTUnwrap(store.photos.first)
        let timer = Task { await model.waitForAutoClose(after: .milliseconds(20)) }
        await Task.yield()
        XCTAssertTrue(model.retake())
        XCTAssertNil(model.captured)
        XCTAssertTrue(store.photos.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.imageURL(for: oldPhoto).path))
        let shouldClose = await timer.value
        XCTAssertFalse(shouldClose)
        model.capture(image())
        XCTAssertEqual(store.photos.count, 1)
        XCTAssertNotEqual(store.photos[0].id, oldPhoto.id)
    }

    func testCancelledCloseTimerDoesNotDismiss() async {
        let (store, _, _) = makeStore()
        let model = QuickCaptureViewModel(store: store)
        model.capture(image())
        let timer = Task { await model.waitForAutoClose(after: .seconds(3)) }
        await Task.yield()
        timer.cancel()
        let shouldClose = await timer.value
        XCTAssertFalse(shouldClose)
    }

    private func makeStore(directory: URL? = nil) -> (PendingPhotoStore, ControlledPhotoUploader, PhotoAuthFlag) {
        let uploader = ControlledPhotoUploader()
        let auth = PhotoAuthFlag()
        let store = PendingPhotoStore(directory: directory ?? temporaryDirectory(), uploader: uploader,
                                      isAuthenticated: { auth.value }, onActivity: { _ in })
        return (store, uploader, auth)
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoWorkflow-\(UUID())")
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
            UIColor.systemYellow.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
    }
}

@MainActor
private final class PhotoAuthFlag { var value = false }

@MainActor
private final class ControlledPhotoUploader: PhotoUploading {
    let serverID = UUID()
    var calls = 0
    var shouldFail = false
    var suspendFirst = false
    var continuation: CheckedContinuation<UUID, Error>?
    var receivedCheckpoints: [PhotoUploadCheckpoint?] = []

    func upload(imageData: Data, context: IntakeContext, checkpoint: PhotoUploadCheckpoint?,
                onCheckpoint: @escaping (PhotoUploadCheckpoint) throws -> Void) async throws -> UUID {
        calls += 1
        receivedCheckpoints.append(checkpoint)
        try onCheckpoint(checkpoint ?? PhotoUploadCheckpoint(photoId: serverID,
            uploadURL: URL(string: "https://example.invalid/upload")!, expiresAt: .now.addingTimeInterval(300)))
        if shouldFail { throw URLError(.notConnectedToInternet) }
        if suspendFirst && calls == 1 {
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        return serverID
    }
}

@MainActor
private final class PhotoTransportDouble: PhotoUploadTransport {
    let photoID = UUID()
    var starts = 0
    var puts = 0
    var completionIDs: [UUID] = []
    var hasBytes = false
    var losePutResponse = false
    var failCompletionOnce = false

    func start(context: IntakeContext) async throws -> PhotoUploadCheckpoint {
        starts += 1
        return PhotoUploadCheckpoint(photoId: photoID, uploadURL: URL(string: "https://example.invalid/upload")!,
                                     expiresAt: .now.addingTimeInterval(300))
    }

    func put(imageData: Data, url: URL, onProgress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        puts += 1
        hasBytes = true
        if losePutResponse { losePutResponse = false; throw URLError(.networkConnectionLost) }
    }

    func complete(photoId: UUID) async throws {
        completionIDs.append(photoId)
        if failCompletionOnce { failCompletionOnce = false; throw URLError(.networkConnectionLost) }
        if !hasBytes {
            throw APIError.server(status: 409, body: APIErrorBody(code: "PHOTO_NOT_UPLOADED", message: "", requestId: nil))
        }
    }
}
