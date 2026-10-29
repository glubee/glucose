import SwiftUI
import UIKit

struct PendingPhotoDetailView: View {
    let photoID: UUID
    let store: PendingPhotoStore
    let onFinished: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsDeleteConfirm = false
    @State private var showsError = false

    private var photo: PendingPhoto? { store.photos.first { $0.id == photoID } }

    var body: some View {
        Group {
            if let photo, photo.hasConfirmedRecord {
                confirmed(photo)
            } else if let photo, let serverID = photo.photoId {
                RecognitionResultView(photoId: serverID, context: photo.context, occurredAt: photo.capturedAt,
                    previewImage: UIImage(contentsOfFile: store.imageURL(for: photo).path),
                    onDeletePhoto: { remove() }) {
                        if store.finishConfirmation(photoID) { onFinished() }
                        else { showsError = true }
                    }
            } else if let photo {
                waiting(photo)
            } else {
                StateView(kind: .empty, title: "이 사진은 목록에서 지워졌어요",
                          actionTitle: "목록으로 돌아가기", action: onFinished)
            }
        }
        .alert(store.errorMessage ?? "사진을 정리하지 못했어요. 다시 시도해 주세요.", isPresented: $showsError) {
            Button("확인", role: .cancel) {}
        }
    }

    private func confirmed(_ photo: PendingPhoto) -> some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            Text("기록은 이미 저장됐어요")
                .font(.headline1).foregroundStyle(Color.textPrimary)
            Text("다시 저장하지 않고 남은 기기 사진만 정리해요.")
                .font(.body2).foregroundStyle(Color.textSecondary)
            Button("기기 사진 정리하기") { _ = remove() }
                .buttonStyle(.glubeePrimary)
            Spacer()
        }
        .padding(Spacing.gutter)
        .navigationTitle("사진 정리")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
        }
    }

    private func waiting(_ photo: PendingPhoto) -> some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                if let image = UIImage(contentsOfFile: store.imageURL(for: photo).path) {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                        .accessibilityLabel("확인 대기 사진")
                }
                Text(photo.capturedAt.formatted(.dateTime.month().day().hour().minute()))
                    .font(.headline2).foregroundStyle(Color.textPrimary)
                Text(store.statusMessage(for: photo)).font(.body2).foregroundStyle(Color.textSecondary)
                if store.status(for: photo) == .uploading { ProgressView() }
                else if store.canUpload {
                    Button("다시 시도") { Task { await store.uploadPending() } }
                        .buttonStyle(.glubeePrimary).disabled(store.isUploading)
                }
                Button("사진 지우기", role: .destructive) { showsDeleteConfirm = true }
                    .buttonStyle(.glubeeSecondary)
                    .accessibilityIdentifier("deletePendingPhoto")
            }
            .padding(Spacing.gutter)
        }
        .background(Color.canvas)
        .navigationTitle("확인 대기 사진")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
        }
        .alert("이 사진을 지울까요?", isPresented: $showsDeleteConfirm) {
            Button("사진 지우기", role: .destructive) { _ = remove() }
            Button("취소", role: .cancel) {}
        } message: { Text(PendingPhotoDeletion.message) }
    }

    @discardableResult
    private func remove() -> Bool {
        if store.remove(photoID) { onFinished(); return true }
        showsError = true
        return false
    }
}
