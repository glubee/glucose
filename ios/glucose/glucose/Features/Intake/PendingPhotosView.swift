//
//  PendingPhotosView.swift
//  glucose
//
//  홈의 "확인 안 한 사진"에서 여는 목록. 위젯으로 찍은 사진을 하루 마무리 전에 바로 확인할 수 있게 한다.
//  누르면 음식 확인 화면, 저장하면 목록에서 빠진다. 하루 마무리의 사진 단계와 같은 저장소를 쓴다.
//

import SwiftUI

struct PendingPhotosView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [PendingPhoto] = []
    private let store = PendingPhotoStore.shared

    private var photos: [PendingPhoto] {
        store.photos.sorted { $0.capturedAt > $1.capturedAt }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    if photos.isEmpty {
                        StateView(kind: .empty, title: "확인할 사진이 없어요",
                                  message: "위젯으로 찍은 사진은 여기와 하루 마무리에서 확인해요.")
                    } else {
                        Text("눌러서 어떤 음식인지 확인해 주세요. 찍은 시각으로 기록돼요.")
                            .font(.body2)
                            .foregroundStyle(Color.textSecondary)
                        ForEach(photos) { photo in
                            row(photo)
                        }
                    }
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.m)
            }
            .background(Color.canvas)
            .navigationTitle("확인 안 한 사진")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .navigationDestination(for: PendingPhoto.self) { photo in
                if let photoId = photo.photoId {
                    RecognitionResultView(photoId: photoId, context: photo.context, occurredAt: photo.capturedAt) {
                        store.remove(photo.id)
                        path.removeAll()
                    }
                }
            }
            .task { await store.uploadPending() }
            .refreshable { await store.uploadPending() }
        }
    }

    private func row(_ photo: PendingPhoto) -> some View {
        HStack(spacing: Spacing.s) {
            thumbnail(photo)
            VStack(alignment: .leading, spacing: 2) {
                Text(timeTitle(photo.capturedAt))
                    .font(.headline2)
                    .foregroundStyle(Color.textPrimary)
                Text(status(photo))
                    .font(.caption1)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            if photo.photoId != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            } else if store.isUploading {
                ProgressView()
            } else {
                Button("다시 시도") { Task { await store.uploadPending() } }
                    .font(.caption1.weight(.semibold))
            }
        }
        .card(padding: Spacing.s)
        .contentShape(Rectangle())
        .onTapGesture {
            if photo.photoId != nil { path.append(photo) }
        }
        .contextMenu {
            Button("사진 지우기", systemImage: "trash", role: .destructive) { store.remove(photo.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(photo.photoId != nil ? .isButton : [])
    }

    @ViewBuilder
    private func thumbnail(_ photo: PendingPhoto) -> some View {
        if let image = UIImage(contentsOfFile: store.imageURL(for: photo).path) {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: Radius.field))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "photo")
                .foregroundStyle(Color.onBrandSoft)
                .frame(width: 56, height: 56)
                .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: Radius.field))
                .accessibilityHidden(true)
        }
    }

    private func timeTitle(_ date: Date) -> String {
        let calendar = ReportDay.calendar
        let time = ReportDay.timeString(from: date)
        if calendar.isDateInToday(date) { return "오늘 \(time)" }
        if calendar.isDateInYesterday(date) { return "어제 \(time)" }
        return "\(date.formatted(.dateTime.month().day())) \(time)"
    }

    private func status(_ photo: PendingPhoto) -> String {
        if photo.photoId != nil { return "확인 필요" }
        if store.isUploading { return "올리는 중" }
        return photo.uploadFailed ? "올리지 못했어요" : "아직 올리지 않았어요"
    }
}

#Preview {
    PendingPhotosView()
}
