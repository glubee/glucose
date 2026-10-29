import SwiftUI
import UIKit

enum PendingPhotoDeletion {
    static let message = "이 기기의 확인 대기 사진을 지워요. 지우면 되돌릴 수 없어요. 서버에 이미 올린 사진은 남아 있을 수 있어요."
}

/// 목록과 하루 마무리에서 같은 상태·재시도·삭제 버튼을 보여준다.
struct PendingPhotoRow: View {
    let photo: PendingPhoto
    let store: PendingPhotoStore
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Button(action: onOpen) {
                HStack(spacing: Spacing.s) {
                    PendingPhotoThumbnail(photo: photo, store: store)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(photo.capturedAt.formatted(.dateTime.month().day().hour().minute()))
                            .font(.headline2).foregroundStyle(Color.textPrimary)
                        Text(store.statusMessage(for: photo))
                            .font(.caption1).foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if store.status(for: photo) == .uploading { ProgressView() }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pendingPhotoOpen-\(photo.id.uuidString)")
            if photo.photoId == nil, store.status(for: photo) != .uploading, store.canUpload {
                Button("다시 시도") { Task { await store.uploadPending() } }
                    .font(.caption1)
                    .disabled(store.isUploading)
            }
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .frame(width: Metrics.minTapTarget, height: Metrics.minTapTarget)
                    .foregroundStyle(Color.alert)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("이 사진 지우기")
            .accessibilityIdentifier("pendingPhotoDelete-\(photo.id.uuidString)")
        }
        .card(padding: Spacing.s)
    }
}

struct PendingPhotoThumbnail: View {
    let photo: PendingPhoto
    let store: PendingPhotoStore
    var size: CGFloat = 56
    var cornerRadius: CGFloat = Radius.field
    var height: CGFloat? = nil

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: store.imageURL(for: photo).path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(Color.onBrandSoft)
            }
        }
        .frame(width: size, height: height ?? size)
        .background(Color.brandSoft)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
    }
}
