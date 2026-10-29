import SwiftUI

/// 홈 "오늘의 흐름" 아래 시간줄: 오늘 남긴 음식·인슐린·확인 대기 사진을 시간순으로 세로 줄에 꿰어 보여주고,
/// 맨 끝에서 바로 음식·인슐린을 더할 수 있다. 점 색은 상황별(식사·간식·저혈당 대응·술·인슐린) 색이다.
struct HomeTimelineSection: View {
    let viewModel: HomeViewModel
    let highlightedID: String?
    let openPending: (PendingPhoto) -> Void
    let takePhoto: () -> Void
    let writeFood: () -> Void
    var addInsulin: () -> Void = {}
    let showAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text("오늘 남긴 기록 \(viewModel.todayEntries.count)건")
                    .font(.pretendard(15, relativeTo: .subheadline, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
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
                }
            } else if !viewModel.timeline.isLoading && viewModel.todayEntries.isEmpty {
                Text("오늘은 아직 남긴 기록이 없어요. 아래에서 첫 기록을 더해 보세요.")
                    .font(.body2).foregroundStyle(Color.textSecondary)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(viewModel.todayEntries.enumerated()), id: \.element.id) { index, entry in
                    railRow(entry, isLast: index == viewModel.todayEntries.count - 1)
                }
            }

            addRow
        }
    }

    // MARK: - 시간줄 한 칸

    private func railRow(_ entry: TimelineEntry, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Text(ReportDay.timeString(from: entry.occurredAt))
                .font(.caption1.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .frame(width: 44, alignment: .trailing)
                .padding(.top, 14)
            VStack(spacing: 0) {
                Circle()
                    .fill(color(for: entry))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(Color.canvas, lineWidth: 2))
                    .padding(.top, 16)
                Rectangle()
                    .fill(Color.line)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .opacity(isLast ? 0 : 1)
            }
            .frame(width: 14)
            Group {
                switch entry {
                case .record(let item):
                    NavigationLink(value: item) { RecordRow(item: item) }.buttonStyle(.plain)
                case .pending(let photo):
                    Button { openPending(photo) } label: { pendingRow(photo) }.buttonStyle(.plain)
                }
            }
            .padding(.bottom, Spacing.xs)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(highlightedID == entry.id ? Color.brand : Color.clear, lineWidth: 3)
                    .padding(.bottom, Spacing.xs)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .id(entry.id)
        .accessibilityIdentifier("timeline-\(entry.id)")
        .accessibilityValue(highlightedID == entry.id ? "새로 추가한 기록" : "")
    }

    private func pendingRow(_ photo: PendingPhoto) -> some View {
        HStack(spacing: Spacing.s) {
            PendingPhotoThumbnail(photo: photo, store: viewModel.photos)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(photo.context.chipName) 사진")
                    .font(.headline2).foregroundStyle(Color.textPrimary)
                Text("확인 필요").font(.body2.weight(.semibold)).foregroundStyle(photo.context.tint)
                Text(viewModel.photos.statusMessage(for: photo))
                    .font(.caption1).foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.textSecondary)
        }
        .card(padding: Spacing.s)
    }

    private func color(for entry: TimelineEntry) -> Color {
        switch entry {
        case .record(.intake(let record)): record.context.tint
        case .record(.insulin): .insulin
        case .pending(let photo): photo.context.tint.opacity(0.5)
        }
    }

    // MARK: - 바로 더하기

    private var addRow: some View {
        HStack(spacing: Spacing.xs) {
            addButton("사진", icon: "camera.fill", tint: IntakeContext.meal.tint, action: takePhoto)
                .accessibilityIdentifier("timelineTakePhoto")
            addButton("글로 음식", icon: "square.and.pencil", tint: IntakeContext.snack.tint, action: writeFood)
                .accessibilityIdentifier("timelineWriteFood")
            addButton("인슐린", icon: "syringe.fill", tint: .insulin, action: addInsulin)
                .accessibilityIdentifier("timelineAddInsulin")
        }
        .padding(.top, Spacing.xxs)
    }

    private func addButton(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.body.weight(.semibold))
                Text("+ \(title)").font(.caption1.weight(.bold))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Color.canvas, in: RoundedRectangle(cornerRadius: Radius.field))
            .overlay(RoundedRectangle(cornerRadius: Radius.field).strokeBorder(tint.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
        .buttonStyle(.plain)
    }
}
