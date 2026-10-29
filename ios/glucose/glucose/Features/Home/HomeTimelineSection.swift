import SwiftUI

/// 홈 "오늘의 다이어리": 하루 마무리와 같은 줄노트가 화면 끝까지 이어지고, 오늘 남긴 음식·인슐린·확인 대기 사진이
/// 시간순으로 바로 붙는다. 사진은 테이프로 붙인 폴라로이드(아래 띠 색 = 상황), 누르면 그 자리에서 보고 고친다.
/// 하루 마무리는 이 시간줄을 마지막으로 한 번 확인하는 단계다. 더하기 버튼은 홈 아래 버튼만 쓴다.
struct HomeTimelineSection: View {
    let viewModel: HomeViewModel
    let highlightedID: String?
    let openPending: (PendingPhoto) -> Void
    let showAll: () -> Void
    @State private var showDayPicker = false

    private static let photoWidth: CGFloat = 136
    private static let photoHeight: CGFloat = 100

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
                .padding(.bottom, Spacing.s)

            if RecordDataSource.isPreview {
                Text("예시 기록 · 서버에 저장되지 않아요")
                    .font(.caption1).foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity)
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
            }

            ForEach(viewModel.todayEntries) { entry in
                row(entry)
            }
            if viewModel.isDiaryToday {
                nowRow
            } else if !viewModel.timeline.isLoading && viewModel.todayEntries.isEmpty {
                Text("이 날 남긴 기록이 없어요.")
                    .font(.body2).foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.l)
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.top, Spacing.m)
        .padding(.bottom, Spacing.xl)
        .frame(maxWidth: .infinity, minHeight: 460, alignment: .top)
        .background(DiaryPaper())
        .sheet(isPresented: $showDayPicker) {
            DayPickerSheet(title: "다이어리 날짜", date: viewModel.diaryDay) { day in
                Task { await viewModel.showDiary(day: day) }
            }
        }
    }

    // MARK: - 머리

    private var heading: some View {
        VStack(spacing: Spacing.xxs) {
            HStack {
                Text(viewModel.isDiaryToday ? "오늘의 다이어리" : "지난 다이어리").font(.body2).foregroundStyle(Color.textSecondary)
                if !viewModel.isDiaryToday {
                    Button("오늘로") { Task { await viewModel.showDiary(day: viewModel.today) } }
                        .font(.body2.weight(.semibold))
                        .foregroundStyle(Diary.ink)
                        .frame(minHeight: Metrics.minTapTarget)
                        .accessibilityIdentifier("diaryToday")
                }
                Spacer()
                Text(stamp)
                    .font(.caption1.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Diary.ink)
                    .padding(.horizontal, Spacing.xs).padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Diary.ink.opacity(0.5), lineWidth: 1))
                    .rotationEffect(.degrees(-3))
            }
            HStack(spacing: Spacing.xs) {
                dayArrow("chevron.left", label: "이전 날 다이어리", enabled: true) {
                    Task { await viewModel.moveDiary(byDays: -1) }
                }
                Spacer(minLength: 0)
                Button { showDayPicker = true } label: {
                    HStack(spacing: Spacing.xxs) {
                        Text(longDate)
                            .font(.pretendard(24, relativeTo: .title, weight: .bold))
                            .minimumScaleFactor(0.8)
                            .lineLimit(1)
                        Image(systemName: "calendar").font(.body.weight(.semibold)).foregroundStyle(Diary.ink)
                    }
                    .foregroundStyle(Color.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(longDate), 눌러서 날짜 고르기")
                .accessibilityIdentifier("diaryDate")
                Spacer(minLength: 0)
                dayArrow("chevron.right", label: "다음 날 다이어리", enabled: viewModel.canDiaryGoForward) {
                    Task { await viewModel.moveDiary(byDays: 1) }
                }
            }
            HStack(spacing: Spacing.xxs) {
                Text(viewModel.todayEntries.isEmpty ? "오늘의 조각을 함께 모아봐요."
                     : "\(viewModel.isDiaryToday ? "오늘" : "이 날") 남긴 조각 \(viewModel.todayEntries.count)개")
                    .font(.body2).foregroundStyle(Color.textSecondary)
                Button(action: showAll) {
                    Text("전체 기록 ›").font(.body2).underline().foregroundStyle(Diary.ink)
                }
                .frame(minHeight: Metrics.minTapTarget)
            }
        }
        .frame(maxWidth: .infinity)
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
                        FoodPhotoThumbnail(photoId: photoId, size: Self.photoWidth, cornerRatio: 0.01,
                                           height: Self.photoHeight)
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
                    linkText("기록 보기 · 수정")
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
                    linkText("기록 보기 · 수정")
                }
            }
        }
    }

    private func pendingContent(_ photo: PendingPhoto) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            DiaryPolaroid(tint: photo.context.tint) {
                PendingPhotoThumbnail(photo: photo, store: viewModel.photos, size: Self.photoWidth,
                                      cornerRadius: 1, height: Self.photoHeight)
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

    /// 시간줄 끝 "지금": 다음 기록이 붙을 자리
    private var nowRow: some View {
        DiaryTimeRow(time: .now, label: "지금", dashed: false) {
            Text(viewModel.todayEntries.isEmpty
                 ? "아래 \"음식 찍기\"나 \"인슐린\"으로 남기면 시간순으로 여기에 붙어요."
                 : "다음 기록도 여기에 이어서 붙어요.")
                .font(.body2)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.s)
                .overlay(RoundedRectangle(cornerRadius: Radius.field)
                    .strokeBorder(Diary.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        }
        .accessibilityElement(children: .combine)
    }

    private func dayArrow(_ systemImage: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 32, height: 32)
                .background(Color.surfaceMuted, in: Circle())
                .frame(width: Metrics.minTapTarget, height: Metrics.minTapTarget)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
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

    private var longDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = ReportDay.calendar.timeZone
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter.string(from: viewModel.diaryDay)
    }

    private var stamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = ReportDay.calendar.timeZone
        formatter.dateFormat = "MM.dd · EEE"
        return formatter.string(from: viewModel.diaryDay).uppercased()
    }
}
