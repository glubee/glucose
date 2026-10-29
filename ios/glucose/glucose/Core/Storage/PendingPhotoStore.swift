import Foundation
import UIKit

struct PendingPhoto: Codable, Identifiable, Hashable {
    let id: UUID
    let capturedAt: Date
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
    static let shared = PendingPhotoStore()
    private(set) var photos: [PendingPhoto] = []
    private(set) var isUploading = false
    private(set) var activeUploadID: UUID?
    private(set) var errorMessage: String?

    private let directory: URL
    private let uploader: PhotoUploading
    private let isAuthenticated: () -> Bool
    private let onActivity: (Bool) -> Void
    private var uploadGeneration = UUID()
    private var activeTask: Task<UUID, Error>?
    private var indexURL: URL { directory.appendingPathComponent("index.json") }
    private var discardedDirectory: URL { directory.appendingPathComponent(".discarded") }
    private var confirmedDirectory: URL { directory.appendingPathComponent(".confirmed") }

    init(directory: URL? = nil, uploader: PhotoUploading? = nil,
         isAuthenticated: (() -> Bool)? = nil, onActivity: ((Bool) -> Void)? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PendingPhotos", isDirectory: true)
        self.uploader = uploader ?? PhotoUploader()
        self.isAuthenticated = isAuthenticated ?? { AuthSession.shared.isAuthenticated }
        self.onActivity = onActivity ?? { recorded in
            WidgetSnapshot.refresh(noteRecord: recorded)
            Task { await NudgeScheduler.refresh() }
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL) {
            do {
                photos = try JSONDecoder().decode([PendingPhoto].self, from: data)
                recoverStoredState()
            }
            catch { errorMessage = "확인 대기 사진 목록을 불러오지 못했어요." }
        }
    }

    var waitingForUpload: Int { photos.filter { $0.photoId == nil }.count }
    var canUpload: Bool { isAuthenticated() }

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
        let photo = PendingPhoto(id: UUID(), capturedAt: capturedAt, context: context)
        do {
            try imageData.write(to: imageURL(for: photo), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try persist(photos + [photo])
            photos.append(photo)
            errorMessage = nil
            onActivity(true)
            if canUpload { Task { await uploadPending() } }
            return photo
        } catch {
            try? FileManager.default.removeItem(at: imageURL(for: photo))
            errorMessage = "사진을 기기에 저장하지 못했어요. 다시 찍어주세요."
            return nil
        }
    }

    func setContext(_ context: IntakeContext, for id: UUID) {
        try? update(id) { $0.context = context }
    }

    func imageURL(for photo: PendingPhoto) -> URL { directory.appendingPathComponent(photo.fileName) }

    /// 기기 대기 목록과 파일만 지운다. 서버 사진에는 DELETE API가 없다.
    @discardableResult
    func remove(_ id: UUID) -> Bool {
        guard let photo = photos.first(where: { $0.id == id }) else { return false }
        let original = imageURL(for: photo)
        let staged = discardedDirectory.appendingPathComponent(photo.fileName)
        var didStage = false
        do {
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

    func removeAll() {
        uploadGeneration = UUID()
        activeTask?.cancel()
        activeTask = nil
        activeUploadID = nil
        isUploading = false
        for photo in photos { try? FileManager.default.removeItem(at: imageURL(for: photo)) }
        try? FileManager.default.removeItem(at: discardedDirectory)
        try? FileManager.default.removeItem(at: confirmedDirectory)
        photos = []
        do { try persist([]); errorMessage = nil }
        catch { errorMessage = "사진 목록을 정리하지 못했어요." }
    }

    func uploadPending() async {
        guard !isUploading, canUpload else { return }
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
                try await uploader.upload(imageData: data, context: photo.context, checkpoint: photo.uploadCheckpoint) { [self] checkpoint in
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
