import XCTest
@testable import glucose

@MainActor
final class PhotoPreservationTests: XCTestCase {
    private func directory() -> URL {
        let value = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: value, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: value) }
        return value
    }
    private func make(_ directory: URL, accountScoped: Bool = false) -> PendingPhotoStore {
        PendingPhotoStore(directory: directory, isAuthenticated: { false }, onActivity: { _ in }, accountScoped: accountScoped)
    }
    private func remote(id: UUID = UUID(), client: UUID? = nil, confirmed: Bool = false) -> SyncedPhoto {
        SyncedPhoto(photoId: id, clientId: client, capturedAt: Date(timeIntervalSince1970: 1_700_000_000), context: .snack,
                    status: "UPLOADED", confirmed: confirmed, dismissed: false)
    }

    func testRemotePhotoRestoresMetadataWithoutLocalBytesOrReupload() async throws {
        let folder = directory(), store = make(folder), service = PhotoSyncDouble()
        let photo = remote(); service.pages[""] = PhotoSyncPage(items: [photo], nextCursor: nil)
        try await store.synchronize(using: service)
        let restored = try XCTUnwrap(store.photos.first)
        XCTAssertEqual(restored.photoId, photo.photoId)
        XCTAssertEqual(restored.context, .snack)
        XCTAssertEqual(restored.capturedAt, photo.capturedAt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.imageURL(for: restored).path))
        XCTAssertEqual(store.waitingForUpload, 0)
        XCTAssertEqual(make(folder).photos.first?.photoId, photo.photoId)
    }

    func testIncompleteOrRepeatedPageCannotReplaceExistingPhotos() async throws {
        let folder = directory(), store = make(folder), service = PhotoSyncDouble()
        let local = try XCTUnwrap(store.add(imageData: Data([1,2]), context: .meal))
        service.pages[""] = PhotoSyncPage(items: [remote()], nextCursor: "next")
        service.pages["next"] = PhotoSyncPage(items: [], nextCursor: "next")
        do { try await store.synchronize(using: service); XCTFail("repeated cursor must fail") } catch {}
        XCTAssertEqual(store.photos.map(\.id), [local.id])
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: local)), Data([1,2]))
    }

    func testDismissalOutboxSurvivesFailureAndRestartWithoutResurrection() async throws {
        let folder = directory(), service = PhotoSyncDouble(), photo = remote()
        service.pages[""] = PhotoSyncPage(items: [photo], nextCursor: nil)
        let store = make(folder); try await store.synchronize(using: service)
        let restored = try XCTUnwrap(store.photos.first)
        XCTAssertTrue(store.remove(restored.id))
        XCTAssertEqual(store.pendingDismissals, 1)
        service.failDismiss = true
        do { try await store.synchronize(using: service) } catch {}
        let restarted = make(folder)
        XCTAssertEqual(restarted.pendingDismissals, 1)
        XCTAssertTrue(restarted.photos.isEmpty)
        service.failDismiss = false
        // A stale list can still include the just-dismissed photo; hide the local tombstone.
        try await restarted.synchronize(using: service)
        XCTAssertEqual(service.dismissed.last, photo.photoId)
        XCTAssertTrue(restarted.photos.isEmpty)
        XCTAssertEqual(restarted.pendingDismissals, 0)
    }

    func testConfirmedPhotoCleanupRequiresSpecificServerState() async throws {
        let folder = directory(), store = make(folder), service = PhotoSyncDouble(), photo = remote()
        service.pages[""] = PhotoSyncPage(items: [photo], nextCursor: nil)
        try await store.synchronize(using: service)
        service.pages[""] = PhotoSyncPage(items: [], nextCursor: nil)
        do { try await store.synchronize(using: service) } catch {}
        XCTAssertEqual(store.photos.count, 1, "missing/failed metadata is not deletion evidence")
        service.details[photo.photoId] = remote(id: photo.photoId, confirmed: true)
        try await store.synchronize(using: service)
        XCTAssertTrue(store.photos.isEmpty)
    }

    func testConfirmationDuringPagingDoesNotResurrectPhoto() async throws {
        let folder = directory(), store = make(folder), service = PhotoSyncDouble(), photo = remote()
        service.pages[""] = PhotoSyncPage(items: [photo], nextCursor: nil)
        try await store.synchronize(using: service)
        let local = try XCTUnwrap(store.photos.first)
        service.pauses = true
        let pending = Task { try await store.synchronize(using: service) }
        while service.continuation == nil { await Task.yield() }
        XCTAssertTrue(store.finishConfirmation(local.id))
        service.continuation?.resume(returning: PhotoSyncPage(items: [photo], nextCursor: nil))
        try await pending.value
        XCTAssertTrue(store.photos.isEmpty)
        XCTAssertEqual(store.pendingDismissals, 0)
    }

    func testUnreadableIndexIsPreservedWhenSyncOrAddIsAttempted() async throws {
        let folder = directory(), index = folder.appendingPathComponent("index.json")
        let original = Data("invalid-index".utf8)
        try original.write(to: index)
        let store = make(folder), service = PhotoSyncDouble()
        service.pages[""] = PhotoSyncPage(items: [remote()], nextCursor: nil)
        do { try await store.synchronize(using: service); XCTFail("must not replace an unreadable index") } catch {}
        XCTAssertNil(store.add(imageData: Data([1]), context: .meal))
        XCTAssertEqual(try Data(contentsOf: index), original)
    }

    func testLegacyPhotoRequiresClaimAndKeepsBytesIfMigrationFails() throws {
        let folder = directory(), legacy = make(folder)
        let original = try XCTUnwrap(legacy.add(imageData: Data([1,2,3]), context: .meal))
        let owner = UUID(), store = make(folder, accountScoped: true)
        store.activateAccount(owner)
        XCTAssertTrue(store.photos.isEmpty)
        let destinationIndex = folder.appendingPathComponent("accounts/\(owner.uuidString)/index.json")
        try FileManager.default.createDirectory(at: destinationIndex, withIntermediateDirectories: true)
        XCTAssertFalse(store.claimLegacyForActiveAccount())
        XCTAssertEqual(try Data(contentsOf: legacy.imageURL(for: original)), Data([1,2,3]))
        try FileManager.default.removeItem(at: destinationIndex)
        XCTAssertTrue(store.claimLegacyForActiveAccount())
        XCTAssertEqual(store.photos.first?.id, original.id)
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: original)), Data([1,2,3]))
        store.activateAccount(UUID(), allowLegacy: true)
        XCTAssertTrue(store.photos.isEmpty)
    }

    func testAccountErasureRemovesOwnedLegacyRemnantsButKeepsOtherAccountFiles() throws {
        let folder = directory(), legacy = make(folder), id = UUID(), other = UUID()
        _ = legacy.add(imageData: Data([1]), context: .meal)
        let store = make(folder, accountScoped: true)
        store.activateAccount(id, allowLegacy: true)
        let remnant = folder.appendingPathComponent(".discarded/old.jpg")
        try FileManager.default.createDirectory(at: remnant.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([2]).write(to: remnant)
        let otherFile = folder.appendingPathComponent("accounts/\(other.uuidString)/keep.jpg")
        try FileManager.default.createDirectory(at: otherFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([3]).write(to: otherFile)
        store.eraseActiveAccount()
        XCTAssertFalse(FileManager.default.fileExists(atPath: remnant.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("legacy-owner.txt").path))
        XCTAssertEqual(try Data(contentsOf: otherFile), Data([3]))
    }

    func testPhotoAccountFoldersRestoreOnlyTheirOwners() throws {
        let folder = directory(), store = make(folder, accountScoped: true), a = UUID(), b = UUID()
        store.activateAccount(a)
        let photo = try XCTUnwrap(store.add(imageData: Data([9]), context: .meal))
        store.activateAccount(b)
        XCTAssertTrue(store.photos.isEmpty)
        store.activateAccount(nil)
        XCTAssertTrue(store.photos.isEmpty)
        store.activateAccount(a)
        XCTAssertEqual(store.photos.map(\.id), [photo.id])
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: photo)), Data([9]))
    }

    func testPreviousAccountResponseCannotPopulateNewAccount() async throws {
        let folder = directory(), store = make(folder, accountScoped: true), service = PhotoSyncDouble()
        store.activateAccount(UUID()); service.pauses = true
        let pending = Task { try await store.synchronize(using: service) }
        while service.continuation == nil && !pending.isCancelled { await Task.yield(); if !service.pauses { break } }
        store.activateAccount(UUID())
        service.continuation?.resume(returning: PhotoSyncPage(items: [remote()], nextCursor: nil))
        do { try await pending.value } catch {}
        XCTAssertTrue(store.photos.isEmpty)
    }
}

@MainActor
private final class PhotoSyncDouble: PhotoSyncServing {
    var pages: [String: PhotoSyncPage] = [:]
    var details: [UUID: SyncedPhoto] = [:]
    var failDismiss = false
    var dismissed: [UUID] = []
    var pauses = false
    var continuation: CheckedContinuation<PhotoSyncPage, Error>?
    func pendingPage(cursor: String?) async throws -> PhotoSyncPage {
        if pauses { pauses = false; return try await withCheckedThrowingContinuation { continuation = $0 } }
        guard let page = pages[cursor ?? ""] else { throw APIError.invalidResponse }; return page
    }
    func metadata(_ id: UUID) async throws -> SyncedPhoto {
        guard let value = details[id] else { throw APIError.invalidResponse }; return value
    }
    func updateMetadata(_ id: UUID, value: PhotoMetadataUpdate) async throws {}
    func dismiss(_ id: UUID) async throws {
        if failDismiss { throw APIError.invalidResponse }; dismissed.append(id)
    }
}
