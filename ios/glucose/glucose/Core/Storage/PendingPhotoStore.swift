//
//  PendingPhotoStore.swift
//  glucose
//
//  빠른 촬영으로 찍었지만 아직 확인(기록 생성)하지 않은 사진. 하루 마무리에서 확인한다.
//  서버에 "확인 대기 사진 목록" API가 없어서 기기에만 둔다(docs/ios-design-v4.md 0장).
//  사진 파일은 앱 전용 폴더에 잠금 보호로 저장하고, 확인이 끝나면 지운다.
//

import Foundation
import UIKit

struct PendingPhoto: Codable, Identifiable, Equatable {
    let id: UUID
    /// 기록 시각은 업로드 시각이 아니라 촬영 시각
    let capturedAt: Date
    var context: IntakeContext
    /// 업로드가 끝나면 채워진다
    var photoId: UUID?
    var uploadFailed = false

    var fileName: String { "\(id.uuidString).jpg" }
}

@MainActor
@Observable
final class PendingPhotoStore {

    static let shared = PendingPhotoStore()

    private(set) var photos: [PendingPhoto] = []
    private(set) var isUploading = false

    private let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PendingPhotos", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([PendingPhoto].self, from: data) {
            photos = decoded
        }
    }

    var waitingForUpload: Int { photos.filter { $0.photoId == nil }.count }

    /// 찍은 사진을 저장하고 바로 업로드를 시작한다
    @discardableResult
    func add(imageData: Data, context: IntakeContext, capturedAt: Date = .now) -> PendingPhoto? {
        let photo = PendingPhoto(id: UUID(), capturedAt: capturedAt, context: context)
        do {
            try imageData.write(to: imageURL(for: photo), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            return nil
        }
        photos.append(photo)
        save()
        Task { await uploadPending() }
        return photo
    }

    func setContext(_ context: IntakeContext, for id: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].context = context
        save()
    }

    func imageURL(for photo: PendingPhoto) -> URL {
        directory.appendingPathComponent(photo.fileName)
    }

    /// 하루 마무리에서 기록으로 확인했거나 사용자가 지웠을 때
    func remove(_ id: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: imageURL(for: photos[index]))
        photos.remove(at: index)
        save()
    }

    /// 아직 안 올라간 사진을 차례로 올린다. 앱이 다시 열릴 때도 부른다.
    /// 앱이 백그라운드로 가도 끝낼 수 있게 시간을 요청한다
    func uploadPending() async {
        guard !isUploading, AuthSession.shared.isAuthenticated else { return }
        isUploading = true
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "pending-photo-upload")
        defer {
            isUploading = false
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }

        for photo in photos where photo.photoId == nil {
            guard let data = try? Data(contentsOf: imageURL(for: photo)) else { continue }
            do {
                let photoId = try await PhotoUploader().upload(imageData: data, context: photo.context)
                update(photo.id) { $0.photoId = photoId; $0.uploadFailed = false }
            } catch {
                update(photo.id) { $0.uploadFailed = true }
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout PendingPhoto) -> Void) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        change(&photos[index])
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(photos) else { return }
        try? data.write(to: indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
