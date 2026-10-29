import Foundation
import UIKit

struct PendingPhoto: Codable, Identifiable, Hashable {
    let id: UUID
    var capturedAt: Date
    var context: IntakeContext
    var photoId: UUID?
    var uploadFailed = false
    var uploadCheckpoint: PhotoUploadCheckpoint?
    var uploadErrorMessage: String?
    var isConfirmed: Bool?

    var fileName: String { "\(id.uuidString).jpg" }
    var hasConfirmedRecord: Bool { isConfirmed == true }
}

enum PendingPhotoUploadStatus: Equatable { case waiting, uploading, failed, ready }

@MainActor
@Observable
final class PendingPhotoStore {
    static let shared = PendingPhotoStore(accountScoped: true)
    private(set) var photos: [PendingPhoto] = []
    private(set) var isUploading = false
    private(set) var activeUploadID: UUID?
    private(set) var errorMessage: String?

    private var directory: URL
    private let baseDirectory: URL
    private let accountScoped: Bool
    private var accountID: UUID?
    private var scopeGeneration = UUID()
    private var storageUnavailable = false
    private struct Dismissal: Codable { let localID: UUID; var acknowledged = false }
    private var dismissals: [UUID: Dismissal] = [:]
    var onSyncNeeded: (() -> Void)?
    private var dismissalsURL: URL { directory.appendingPathComponent("dismissals.json") }
    private let uploader: PhotoUploading
    private let isAuthenticated: () -> Bool
    private let onActivity: (Bool) -> Void
    private var uploadGeneration = UUID()
    private var activeTask: Task<UUID, Error>?
    private var indexURL: URL { directory.appendingPathComponent("index.json") }
    private var discardedDirectory: URL { directory.appendingPathComponent(".discarded") }
    private var confirmedDirectory: URL { directory.appendingPathComponent(".confirmed") }

    init(directory: URL? = nil, uploader: PhotoUploading? = nil,
         isAuthenticated: (() -> Bool)? = nil, onActivity: ((Bool) -> Void)? = nil, accountScoped: Bool = false) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PendingPhotos", isDirectory: true)
        self.baseDirectory = base
        self.accountScoped = accountScoped
        self.directory = accountScoped ? base.appendingPathComponent("accounts/signed_out") : base
        self.uploader = uploader ?? PhotoUploader()
        self.isAuthenticated = isAuthenticated ?? { AuthSession.shared.isAuthenticated }
        self.onActivity = onActivity ?? { recorded in
            WidgetSnapshot.refresh(noteRecord: recorded)
            Task { await NudgeScheduler.refresh() }
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        loadCurrentDirectory()
    }

    var hasUnclaimedLegacy: Bool {
        FileManager.default.fileExists(atPath: baseDirectory.appendingPathComponent("index.json").path)
            && !FileManager.default.fileExists(atPath: baseDirectory.appendingPathComponent("legacy-owner.txt").path)
    }
    func activateAccount(_ id: UUID?, allowLegacy: Bool = false) {
        guard accountScoped else { return }
        scopeGeneration = UUID(); uploadGeneration = UUID()
        activeTask?.cancel(); activeTask = nil; activeUploadID = nil; isUploading = false
        accountID = id
        directory = baseDirectory.appendingPathComponent("accounts/\(id?.uuidString ?? "signed_out")")
        loadCurrentDirectory()
        if id == nil { photos = []; dismissals = [:] }
        if allowLegacy { claimLegacyForActiveAccount() }
    }
    @discardableResult func claimLegacyForActiveAccount() -> Bool {
        guard let accountID, hasUnclaimedLegacy else { return false }
        let sourceIndex = baseDirectory.appendingPathComponent("index.json")
        do {
            let values = try JSONDecoder().decode([PendingPhoto].self, from: Data(contentsOf: sourceIndex))
            var merged = photos
            for photo in values where !merged.contains(where: { $0.id == photo.id }) {
                for relative in [photo.fileName, ".discarded/\(photo.fileName)", ".confirmed/\(photo.id.uuidString)"] {
                    let source = baseDirectory.appendingPathComponent(relative)
                    let target = directory.appendingPathComponent(relative)
                    if FileManager.default.fileExists(atPath: source.path), !FileManager.default.fileExists(atPath: target.path) {
                        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try FileManager.default.copyItem(at: source, to: target)
                    }
                }
                merged.append(photo)
            }
            try persist(merged)
            try Data(accountID.uuidString.utf8).write(to: baseDirectory.appendingPathComponent("legacy-owner.txt"), options: .atomic)
            photos = merged; recoverStoredState()
            // Source bytes are retained until the owned index AND ownership marker are durable.
            try? FileManager.default.removeItem(at: sourceIndex)
            for photo in values { try? FileManager.default.removeItem(at: baseDirectory.appendingPathComponent(photo.fileName)) }
            onSyncNeeded?()
            return true
        } catch { errorMessage = "기존 사진을 가져오지 못했어요. 원본은 그대로 있어요."; return false }
    }
    var pendingDismissals: Int { dismissals.values.filter { !$0.acknowledged }.count }
    var hasPendingBackup: Bool { waitingForUpload > 0 || pendingDismissals > 0 }

    func synchronize(using service: PhotoSyncServing) async throws {
        guard !storageUnavailable else { throw APIError.invalidResponse }
        let scope = scopeGeneration
        func check() throws {
            try Task.checkCancellation()
            guard scopeGeneration == scope else { throw CancellationError() }
        }
        for (id, item) in dismissals where !item.acknowledged && !photos.contains(where: { $0.id == item.localID }) {
            do { try await service.dismiss(id) }
            catch APIError.server(404, _) { /* already absent for this account */ }
            try check()
            dismissals[id]?.acknowledged = true
            try persistDismissals()
        }
        // Older uploads did not carry captured_at/client_id. Fill them from the owned local index.
        for photo in photos where photo.photoId != nil && !photo.hasConfirmedRecord
            && FileManager.default.fileExists(atPath: imageURL(for: photo).path) {
            try await service.updateMetadata(photo.photoId!, value: PhotoMetadataUpdate(capturedAt: photo.capturedAt, clientId: photo.id, context: photo.context))
            try check()
        }
        var remote: [SyncedPhoto] = [], cursor: String?, seen = Set<String>()
        repeat {
            let page = try await service.pendingPage(cursor: cursor)
            try check()
            guard page.items.allSatisfy({ $0.status == "UPLOADED" && !$0.confirmed && !$0.dismissed }) else { throw APIError.invalidResponse }
            remote += page.items
            cursor = page.nextCursor
            if let cursor { guard seen.insert(cursor).inserted, seen.count < 1000 else { throw APIError.invalidResponse } }
        } while cursor != nil
        let remoteIDs = Set(remote.map(\.photoId))
        var resolved = Set<UUID>()
        for photo in photos where photo.photoId != nil && !remoteIDs.contains(photo.photoId!) && !photo.hasConfirmedRecord {
            let detail = try await service.metadata(photo.photoId!)
            try check()
            guard detail.photoId == photo.photoId else { throw APIError.invalidResponse }
            if detail.confirmed || detail.dismissed { resolved.insert(photo.id) }
        }
        try check()
        var merged = photos
        for item in remote where dismissals[item.photoId] == nil {
            if let index = merged.firstIndex(where: { $0.photoId == item.photoId || (item.clientId != nil && $0.id == item.clientId) }) {
                // A confirmation during paging must not be undone by an older pending response.
                guard !merged[index].hasConfirmedRecord else { continue }
                merged[index].photoId = item.photoId
                merged[index].capturedAt = item.capturedAt
                merged[index].context = item.context
                merged[index].uploadFailed = false
                merged[index].uploadCheckpoint = nil
            } else {
                merged.append(PendingPhoto(id: item.clientId ?? item.photoId, capturedAt: item.capturedAt, context: item.context, photoId: item.photoId))
            }
        }
        try persist(merged)
        photos = merged
        for id in resolved { _ = remove(id, remoteDismiss: false) }
    }

    private func loadCurrentDirectory() {
        photos = []; dismissals = [:]; errorMessage = nil; storageUnavailable = false
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL) {
            do { photos = try JSONDecoder().decode([PendingPhoto].self, from: data); recoverStoredState() }
            catch { storageUnavailable = true; errorMessage = "확인 대기 사진 목록을 불러오지 못했어요." }
        }
        if let data = try? Data(contentsOf: dismissalsURL) {
            do { dismissals = try JSONDecoder().decode([UUID: Dismissal].self, from: data) }
            catch { storageUnavailable = true; errorMessage = "사진 정리 목록을 불러오지 못했어요." }
        }
    }
    private func persistDismissals() throws {
        try JSONEncoder().encode(dismissals).write(to: dismissalsURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    var waitingForUpload: Int { photos.filter { $0.photoId == nil }.count }
    var canUpload: Bool { isAuthenticated() && (!accountScoped || accountID != nil) }

    func status(for photo: PendingPhoto) -> PendingPhotoUploadStatus {
        if photo.photoId != nil { return .ready }
        if activeUploadID == photo.id { return .uploading }
        return photo.uploadFailed ? .failed : .waiting
    }

    func statusMessage(for photo: PendingPhoto) -> String {
        if photo.hasConfirmedRecord { return "기록 저장됨 · 기기 사진 정리 필요" }
        return switch status(for: photo) {
        case .ready: "확인 필요"
        case .uploading: "이 사진을 올리는 중이에요"
        case .failed: photo.uploadErrorMessage ?? "올리지 못했어요. 다시 시도해 주세요."
        case .waiting:
            !canUpload ? "로그인하면 자동으로 올려요" : "올리기 대기 중이에요"
        }
    }

    @discardableResult
    func add(imageData: Data, context: IntakeContext, capturedAt: Date = .now) -> PendingPhoto? {
        guard !storageUnavailable else { return nil }
        let photo = PendingPhoto(id: UUID(), capturedAt: capturedAt, context: context)
        do {
            try imageData.write(to: imageURL(for: photo), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try persist(photos + [photo])
            photos.append(photo)
            errorMessage = nil
            onActivity(true)
            onSyncNeeded?()
            if canUpload { Task { await uploadPending() } }
            return photo
        } catch {
            try? FileManager.default.removeItem(at: imageURL(for: photo))
            errorMessage = "사진을 기기에 저장하지 못했어요. 다시 찍어주세요."
            return nil
        }
    }

    func setContext(_ context: IntakeContext, for id: UUID) {
        do { try update(id) { $0.context = context }; onSyncNeeded?() }
        catch { errorMessage = "사진 분류를 저장하지 못했어요." }
    }

    func imageURL(for photo: PendingPhoto) -> URL { directory.appendingPathComponent(photo.fileName) }

    /// 기기 대기 목록과 파일만 지운다. 서버 사진에는 DELETE API가 없다.
    @discardableResult
    func remove(_ id: UUID, remoteDismiss: Bool = true) -> Bool {
        guard let photo = photos.first(where: { $0.id == id }) else { return false }
        let original = imageURL(for: photo)
        let staged = discardedDirectory.appendingPathComponent(photo.fileName)
        var didStage = false
        do {
            if let serverID = photo.photoId ?? photo.uploadCheckpoint?.photoId {
                // Retain even acknowledged tombstones: an older pending page may still arrive.
                dismissals[serverID] = Dismissal(localID: id, acknowledged: !remoteDismiss || photo.hasConfirmedRecord)
                try persistDismissals()
            }
            // 바이트를 먼저 없애지 않는다. index 저장 실패나 중간 종료 시 되돌릴 수 있게 옮긴다.
            if FileManager.default.fileExists(atPath: original.path) {
                try FileManager.default.createDirectory(at: discardedDirectory, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: original, to: staged)
                didStage = true
            }
            let remaining = photos.filter { $0.id != id }
            try persist(remaining)
            photos = remaining
            if activeUploadID == id { activeTask?.cancel() }
            if didStage { try? FileManager.default.removeItem(at: staged) }
            try? FileManager.default.removeItem(at: confirmedDirectory.appendingPathComponent(id.uuidString))
            errorMessage = nil
            onActivity(false)
            onSyncNeeded?()
            return true
        } catch {
            if didStage { try? FileManager.default.moveItem(at: staged, to: original) }
            errorMessage = "사진을 지우지 못했어요. 다시 시도해 주세요."
            return false
        }
    }

    /// 서버 기록은 이미 저장됐다. 정리가 실패해도 이 사진을 다시 POST하지 않도록 완료를 별도로 남긴다.
    @discardableResult
    func finishConfirmation(_ id: UUID) -> Bool {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return true }
        photos[index].isConfirmed = true
        do {
            try FileManager.default.createDirectory(at: confirmedDirectory, withIntermediateDirectories: true)
            try Data().write(to: confirmedDirectory.appendingPathComponent(id.uuidString),
                             options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { errorMessage = "기록은 저장됐지만 기기 사진 정리를 마치지 못했어요." }
        do { try persist(photos) }
        catch { errorMessage = "기록은 저장됐지만 기기 사진 정리를 마치지 못했어요." }
        return remove(id)
    }

    func suspendUploads() {
        scopeGeneration = UUID()
        uploadGeneration = UUID()
        activeTask?.cancel(); activeTask = nil; activeUploadID = nil; isUploading = false
    }

    func removeAll() {
        scopeGeneration = UUID()
        suspendUploads()
        photos = []; dismissals = [:]
        do {
            if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try persist([])
            storageUnavailable = false; errorMessage = nil
        } catch { storageUnavailable = true; errorMessage = "사진 목록을 정리하지 못했어요." }
    }

    func uploadPending() async {
        guard !isUploading, canUpload, !storageUnavailable else { return }
        let generation = UUID()
        uploadGeneration = generation
        isUploading = true
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "pending-photo-upload")
        defer {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            if uploadGeneration == generation {
                isUploading = false
                activeUploadID = nil
                activeTask = nil
            }
        }
        var attempted = Set<UUID>()
        while uploadGeneration == generation, !Task.isCancelled, canUpload,
              let photo = photos.first(where: { $0.photoId == nil && !$0.hasConfirmedRecord && !attempted.contains($0.id) }) {
            attempted.insert(photo.id)
            guard let data = try? Data(contentsOf: imageURL(for: photo)) else {
                try? update(photo.id) {
                    $0.uploadFailed = true
                    $0.uploadErrorMessage = "기기에서 사진을 찾지 못했어요. 지우고 다시 찍어주세요."
                }
                continue
            }
            activeUploadID = photo.id
            let task = Task {
                try await uploader.upload(imageData: data, context: photo.context, capturedAt: photo.capturedAt, clientID: photo.id, checkpoint: photo.uploadCheckpoint) { [self] checkpoint in
                    guard uploadGeneration == generation, photos.contains(where: { $0.id == photo.id }) else {
                        throw CancellationError()
                    }
                    try update(photo.id) { $0.uploadCheckpoint = checkpoint }
                }
            }
            activeTask = task
            do {
                let serverID = try await task.value
                guard uploadGeneration == generation else { return }
                if photos.contains(where: { $0.id == photo.id }) {
                    try update(photo.id) {
                        $0.photoId = serverID
                        $0.uploadFailed = false
                        $0.uploadErrorMessage = nil
                        $0.uploadCheckpoint = nil
                    }
                }
            } catch {
                guard uploadGeneration == generation else { return }
                try? update(photo.id) {
                    $0.uploadFailed = true
                    $0.uploadErrorMessage = "올리지 못했어요. 다시 시도해 주세요."
                }
            }
            guard uploadGeneration == generation else { return }
            activeUploadID = nil
            activeTask = nil
        }
        if !attempted.isEmpty { onSyncNeeded?() }
    }

    private func update(_ id: UUID, _ change: (inout PendingPhoto) -> Void) throws {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        var updated = photos
        change(&updated[index])
        try persist(updated)
        photos = updated
    }

    private func persist(_ values: [PendingPhoto]) throws {
        try JSONEncoder().encode(values).write(to: indexURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func recoverStoredState() {
        if let staged = try? FileManager.default.contentsOfDirectory(at: discardedDirectory, includingPropertiesForKeys: nil) {
            for file in staged {
                if photos.contains(where: { $0.fileName == file.lastPathComponent }) {
                    let original = directory.appendingPathComponent(file.lastPathComponent)
                    if !FileManager.default.fileExists(atPath: original.path) {
                        try? FileManager.default.moveItem(at: file, to: original)
                    }
                } else {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
        for index in photos.indices {
            if FileManager.default.fileExists(atPath: confirmedDirectory.appendingPathComponent(photos[index].id.uuidString).path) {
                photos[index].isConfirmed = true
            }
        }
    }
}
