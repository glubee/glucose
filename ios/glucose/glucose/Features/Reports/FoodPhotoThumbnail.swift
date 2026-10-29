//
//  FoodPhotoThumbnail.swift
//  glucose
//
//  기록한 음식 사진 작은 그림. 서버에서 짧게 쓰는 보기 주소(GET /v1/photos/{id}/view)를 받아 불러온다.
//  주소는 앱이 켜져 있는 동안만 메모리에 두고, 기기에 저장하지 않는다.
//

import SwiftUI

struct FoodPhotoThumbnail: View {
    let photoId: UUID
    var size: CGFloat = 44
    /// 모서리 둥글기(크기 대비). 폴라로이드처럼 각진 사진은 작게
    var cornerRatio: CGFloat = 0.25

    @State private var url: URL?
    @State private var failed = false

    var body: some View {
        Group {
            #if DEBUG
            if let sample = ReportSamples.image(for: photoId) {
                Image(uiImage: sample).resizable().scaledToFill()
            } else {
                remoteImage
            }
            #else
            remoteImage
            #endif
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * cornerRatio))
        .overlay(RoundedRectangle(cornerRadius: size * cornerRatio).strokeBorder(Color.canvas, lineWidth: cornerRatio > 0.1 ? 1.5 : 0))
        .accessibilityLabel("음식 사진")
        .task(id: photoId) {
            url = nil
            failed = false
            #if DEBUG
            if ReportSamples.isEnabled { return }
            #endif
            let loaded = await PhotoViewURLCache.shared.url(for: photoId)
            guard !Task.isCancelled else { return }
            url = loaded
            failed = loaded == nil
        }
    }

    private var remoteImage: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: placeholder("photo")
                    default: Color.surfaceMuted
                    }
                }
            } else {
                placeholder(failed ? "photo" : "")
            }
        }
    }

    private func placeholder(_ icon: String) -> some View {
        ZStack {
            Color.brandSoft
            if !icon.isEmpty {
                Image(systemName: icon).font(.caption).foregroundStyle(Color.onBrandSoft)
            }
        }
    }
}

/// 사진 보기 주소를 만료 전까지 다시 쓰고, 같은 사진을 동시에 여러 번 요청하지 않는다
@MainActor
final class PhotoViewURLCache {
    static let shared = PhotoViewURLCache()

    private struct Entry {
        let url: URL
        let expiresAt: Date
    }

    private struct ViewResponse: Decodable {
        let url: URL
        let expiresIn: Int
    }

    private var entries: [UUID: Entry] = [:]
    private var inFlight: [UUID: Task<URL?, Never>] = [:]

    func invalidate(_ photoId: UUID) { entries[photoId] = nil }

    func url(for photoId: UUID) async -> URL? {
        if let entry = entries[photoId], entry.expiresAt > .now.addingTimeInterval(30) { return entry.url }
        if let task = inFlight[photoId] { return await task.value }
        let task = Task<URL?, Never> {
            guard let response: ViewResponse = try? await APIClient.shared.send(path: "/v1/photos/\(photoId.uuidString)/view")
            else { return nil }
            entries[photoId] = Entry(url: response.url, expiresAt: .now.addingTimeInterval(TimeInterval(response.expiresIn)))
            return response.url
        }
        inFlight[photoId] = task
        let result = await task.value
        inFlight[photoId] = nil
        return result
    }
}
