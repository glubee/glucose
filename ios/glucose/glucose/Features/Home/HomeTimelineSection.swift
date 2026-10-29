import SwiftUI

struct HomeTimelineSection: View {
    let viewModel: HomeViewModel
    let highlightedID: String?
    let openPending: (PendingPhoto) -> Void
    let takePhoto: () -> Void
    let writeFood: () -> Void
    let showAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                SectionHeader(title: "오늘 기록", trailing: "\(viewModel.todayEntries.count)건")
                Button("전체 기록", action: showAll).font(.caption1.weight(.semibold))
                    .foregroundStyle(Color.textSecondary).frame(minHeight: 44)
            }
            if RecordDataSource.isPreview {
                Text("예시 기록 · 서버에 저장되지 않아요").font(.caption1).foregroundStyle(Color.textSecondary)
            }
            if viewModel.timeline.isLoading && viewModel.todayEntries.isEmpty {
                ProgressView("오늘 기록을 불러오고 있어요").frame(maxWidth: .infinity).padding()
            }
            if let error = viewModel.timeline.errorMessage {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(error).font(.body2).foregroundStyle(Color.textSecondary)
                    Button("다시 불러오기") { Task { await viewModel.refresh() } }
                        .font(.body2.weight(.semibold)).frame(minHeight: 44)
                }.card()
            } else if !viewModel.timeline.isLoading && viewModel.todayEntries.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("오늘은 아직 남긴 기록이 없어요").font(.body1)
                    Text("사진을 찍거나 글로 첫 기록을 남겨보세요.").font(.body2).foregroundStyle(Color.textSecondary)
                    Button(action: takePhoto) { Label("음식 찍기", systemImage: "camera") }.buttonStyle(.glubeeAccent)
                    Button("글로 남기기", action: writeFood).buttonStyle(.glubeeSecondary)
                        .accessibilityIdentifier("timelineWriteFood")
                }.card()
            }
            ForEach(viewModel.todayEntries) { entry in
                Group {
                    switch entry {
                    case .record(let item):
                        NavigationLink(value: item) { RecordRow(item: item) }.buttonStyle(.plain)
                    case .pending(let photo):
                        Button { openPending(photo) } label: {
                            HStack(spacing: Spacing.s) {
                                PendingPhotoThumbnail(photo: photo, store: viewModel.photos)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(ReportDay.timeString(from: photo.capturedAt)) · \(photo.context.displayName)")
                                        .font(.headline2).foregroundStyle(Color.textPrimary)
                                    Text("확인 필요").font(.body2.weight(.semibold)).foregroundStyle(Color.onBrandSoft)
                                    Text(viewModel.photos.statusMessage(for: photo))
                                        .font(.caption1).foregroundStyle(Color.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.textSecondary)
                            }.card(padding: Spacing.s)
                        }.buttonStyle(.plain)
                    }
                }
                .id(entry.id)
                .accessibilityIdentifier("timeline-\(entry.id)")
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card)
                        .strokeBorder(highlightedID == entry.id ? Color.brand : Color.clear, lineWidth: 3)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                .accessibilityValue(highlightedID == entry.id ? "새로 추가한 기록" : "")
            }
        }
    }
}
