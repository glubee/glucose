import SwiftUI

/// 홈 "오늘의 다이어리": 오늘 남긴 음식·인슐린·확인 대기 사진을 하루 마무리와 같은 줄노트 시간줄로 보여준다.
/// 왼쪽은 시각과 때(아침·점심·저녁), 사진은 테이프로 붙인 폴라로이드(아래 띠 색 = 상황). 더하기 버튼은 홈 아래 버튼만 쓴다.
struct HomeTimelineSection: View {
    let viewModel: HomeViewModel
    let highlightedID: String?
    let openPending: (PendingPhoto) -> Void
    let showAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("오늘의 다이어리")
                        .font(.pretendard(17, relativeTo: .headline, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text(viewModel.todayEntries.isEmpty ? "남긴 기록이 시간순으로 여기에 붙어요"
                         : "오늘 남긴 기록 \(viewModel.todayEntries.count)개")
                        .font(.caption1)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Button(action: showAll) {
                    Text("전체 기록 ›").font(.body2).underline().foregroundStyle(Diary.ink)
                }
                .frame(minHeight: Metrics.minTapTarget)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.top, Spacing.s)

            if RecordDataSource.isPreview {
                Text("예시 기록 · 서버에 저장되지 않아요")
                    .font(.caption1).foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, Spacing.m)
            }
            if viewModel.timeline.isLoading && viewModel.todayEntries.isEmpty {
                ProgressView("오늘 기록을 불러오고 있어요").frame(maxWidth: .infinity).padding()
            }
            if let error = viewModel.timeline.errorMessage {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(error).font(.body2).foregroundStyle(Color.textSecondary)
                    Button("다시 불러오기") { Task { await viewModel.refresh() } }
                        .font(.body2.weight(.semibold)).frame(minHeight: 44)
                }
                .padding(.horizontal, Spacing.m)
            } else if !viewModel.timeline.isLoading && viewModel.todayEntries.isEmpty {
                Text("아래 \"음식 찍기\"나 \"인슐린\"으로 남기면 시간순으로 여기에 붙어요.")
                    .font(.body2)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, Spacing.m)
                    .padding(.vertical, Spacing.l)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.todayEntries) { entry in
                    row(entry)
                }
            }
            .padding(.horizontal, Spacing.s)
            .padding(.bottom, Spacing.s)
        }
        .background(DiaryPaper(marginX: Spacing.s + Diary.timeColumn / 2))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.line, lineWidth: 1))
    }

    // MARK: - 한 칸

    private func row(_ entry: TimelineEntry) -> some View {
        DiaryTimeRow(time: entry.occurredAt, label: label(for: entry)) {
            Group {
                switch entry {
                case .record(let item):
                    NavigationLink(value: item) { recordContent(item) }.buttonStyle(.plain)
                case .pending(let photo):
                    Button { openPending(photo) } label: { pendingContent(photo) }.buttonStyle(.plain)
                }
            }
            .padding(Spacing.xxs)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.field)
                    .strokeBorder(highlightedID == entry.id ? Color.brand : Color.clear, lineWidth: 3)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .id(entry.id)
        .accessibilityIdentifier("timeline-\(entry.id)")
        .accessibilityValue(highlightedID == entry.id ? "새로 추가한 기록" : "")
    }

    private func label(for entry: TimelineEntry) -> String {
        switch entry {
        case .record(.intake(let record)): Diary.label(for: record.occurredAt, context: record.context)
        case .record(.insulin): "인슐린"
        case .pending(let photo): Diary.label(for: photo.capturedAt, context: photo.context)
        }
    }

    @ViewBuilder
    private func recordContent(_ item: RecordItem) -> some View {
        switch item {
        case .intake(let record):
            HStack(alignment: .top, spacing: Spacing.s) {
                if let photoId = record.photoId {
                    DiaryPolaroid(tint: record.context.tint) {
                        FoodPhotoThumbnail(photoId: photoId, size: 104, cornerRatio: 0.01)
                    }
                    .padding(.top, Spacing.xxs)
                    .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(record.items.isEmpty ? record.context.displayName : record.items.map(\.name).joined(separator: " · "))
                        .font(.body1)
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    contextTag(record.context)
                    linkText("기록 보기")
                }
                .padding(.top, Spacing.xs)
                Spacer(minLength: 0)
            }
        case .insulin(let record):
            DiaryNoteCard(tint: .insulin) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("인슐린 기록", systemImage: "syringe.fill")
                        .font(.caption1.weight(.semibold))
                        .foregroundStyle(Color.insulin)
                    Text("\(record.kind) · \(record.units.formattedUnits)U")
                        .font(.body1)
                        .foregroundStyle(Color.textPrimary)
                    linkText("기록 보기")
                }
            }
        }
    }

    private func pendingContent(_ photo: PendingPhoto) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            DiaryPolaroid(tint: photo.context.tint) {
                PendingPhotoThumbnail(photo: photo, store: viewModel.photos, size: 104, cornerRadius: 1)
            }
            .padding(.top, Spacing.xxs)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("\(photo.context.chipName) 사진")
                    .font(.body1)
                    .foregroundStyle(Color.textPrimary)
                Text("확인 필요")
                    .font(.caption1.weight(.semibold))
                    .foregroundStyle(Color.onBrandSoft)
                    .padding(.horizontal, Spacing.xs).padding(.vertical, 2)
                    .background(Color.brandSoft, in: Capsule())
                Text(viewModel.photos.statusMessage(for: photo))
                    .font(.caption1).foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                linkText("확인하기")
            }
            .padding(.top, Spacing.xs)
            Spacer(minLength: 0)
        }
    }

    private func contextTag(_ context: IntakeContext) -> some View {
        Text(context.chipName)
            .font(.caption2.weight(.bold))
            .foregroundStyle(context.tint)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(context.softFill, in: Capsule())
    }

    /// 줄 전체가 버튼이라 링크는 모양만 낸다
    private func linkText(_ title: String) -> some View {
        Text("\(title) ›")
            .font(.body2)
            .underline()
            .foregroundStyle(Diary.ink)
            .padding(.top, 2)
    }
}
