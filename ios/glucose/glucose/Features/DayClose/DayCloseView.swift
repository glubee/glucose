//
//  DayCloseView.swift
//  glucose
//
//  하루 마무리(v5): 위에 단계 막대(그래프 · 사진 확인 · 인슐린 · 완성), 단계마다 한 화면.
//  실패 화면의 글루비는 웃지 않는다.
//

import PhotosUI
import SwiftUI

struct DayCloseView: View {
    @State private var viewModel: DayCloseViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var showHowTo = false
    @State private var showFoodRecord = false
    @State private var showInsulinRecord = false
    @State private var path: [PendingPhoto] = []

    init(day: Date? = nil) {
        _viewModel = State(initialValue: DayCloseViewModel(day: day))
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                if !viewModel.isFinished {
                    stepBar
                }
                Group {
                    switch viewModel.step {
                    case .graph: graphStep
                    case .photos: photosStep
                    case .insulin: insulinStep
                    case .done: DayCompleteView(viewModel: viewModel, onClose: { dismiss() })
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .background(Color.canvas)
            .navigationTitle("하루 마무리")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.step == .graph || viewModel.isFinished {
                        Button("닫기") { dismiss() }
                    } else {
                        Button { viewModel.back() } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("이전 단계")
                    }
                }
            }
            .navigationDestination(for: PendingPhoto.self) { photo in
                if let photoId = photo.photoId {
                    RecognitionResultView(photoId: photoId, context: photo.context, occurredAt: photo.capturedAt) {
                        path.removeAll()
                        Task { await viewModel.confirmed(photo) }
                    }
                }
            }
        }
        .task { await viewModel.refresh() }
        .onChange(of: viewModel.graphUploader.state) { _, _ in
            Task { await viewModel.graphUploadChanged() }
        }
        .onChange(of: pickerItem) { _, item in
            Task { await upload(item) }
        }
        .sheet(isPresented: $showHowTo) { CaptureHowToSheet() }
        .sheet(isPresented: $showFoodRecord, onDismiss: { Task { await viewModel.refresh() } }) { PhotoCaptureView() }
        .sheet(isPresented: $showInsulinRecord, onDismiss: { Task { await viewModel.refresh() } }) { InsulinConfirmView() }
        .animation(.spring(duration: 0.35), value: viewModel.step)
    }

    // MARK: - 단계 막대

    private var stepBar: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(DayCloseViewModel.Step.allCases, id: \.self) { step in
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Capsule()
                        .fill(step.rawValue <= viewModel.step.rawValue ? Color.textPrimary : Color.line)
                        .frame(height: 3)
                    Text(step.title)
                        .font(.sectionLabel)
                        .foregroundStyle(step == viewModel.step ? Color.textPrimary : Color.textSecondary)
                }
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, Spacing.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("하루 마무리 \(viewModel.step.rawValue + 1)단계, \(viewModel.step.title)")
    }

    // MARK: - ① 그래프

    @ViewBuilder
    private var graphStep: some View {
        switch viewModel.graphPhase {
        case .checking:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .needsUpload, .otherDay:
            stepPage(pose: .photo, title: "\(dayWord) 리브레 그래프를\n올려주세요") {
                VStack(spacing: Spacing.m) {
                    PhotosPicker(selection: $pickerItem, matching: .screenshots) {
                        VStack(spacing: Spacing.xs) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.title2)
                                .foregroundStyle(Color.onBrandSoft)
                                .frame(width: 48, height: 48)
                                .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: Radius.field))
                            Text("스크린샷 고르기").font(.headline2).foregroundStyle(Color.textPrimary)
                            Text("리브레 앱 \"오늘\" 그래프 화면을 캡처해서 골라주세요.")
                                .font(.body2).foregroundStyle(Color.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(Spacing.l)
                        .overlay(RoundedRectangle(cornerRadius: Radius.card)
                            .strokeBorder(Color.line, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                    }
                    .buttonStyle(.plain)
                    if case .otherDay(let date) = viewModel.graphPhase {
                        Text("방금 올린 그래프는 \(date) 그래프였어요. \(viewModel.dayTitle) 그래프를 올려주세요.")
                            .font(.body2).foregroundStyle(Color.alert)
                    }
                }
            } actions: {
                Button("캡처하는 법 보기") { showHowTo = true }
                    .font(.body2).foregroundStyle(Color.textSecondary)
            }
        case .uploading, .analyzing:
            stepPage(pose: .magnifier, title: "그래프를 읽고 있어요", centered: true) {
                Text("10초쯤 걸려요. 화면을 닫아도 계속 읽어요.")
                    .font(.body2).foregroundStyle(Color.textSecondary)
                ProgressView().padding(.top, Spacing.s)
            } actions: { EmptyView() }
        case .ready(let coverage):
            stepPage(pose: .happy, title: "그래프를 읽었어요") {
                Text("하루의 \(Int((coverage * 100).rounded()))%를 읽었어요. 아침에 다시 올리면 덮어써요.")
                    .font(.body2).foregroundStyle(Color.textSecondary)
            } actions: {
                Button("다음 · 사진 확인") { viewModel.goToPhotos() }.buttonStyle(.glubeePrimary)
                PhotosPicker("다시 올리기", selection: $pickerItem, matching: .screenshots)
                    .font(.body2).foregroundStyle(Color.textSecondary)
            }
        case .notRecognized:
            stepPage(pose: .think, title: "그래프를 읽지 못했어요") {
                Text("리브레 앱의 \"오늘\" 그래프가 화면에 다 보이게 다시 캡처해 주세요. 잘리거나 가려지면 읽을 수 없어요.")
                    .font(.body2).foregroundStyle(Color.textSecondary)
            } actions: {
                PhotosPicker(selection: $pickerItem, matching: .screenshots) { Text("다른 스크린샷 고르기") }
                    .buttonStyle(.glubeePrimary)
                Button("캡처하는 법 보기") { showHowTo = true }
                    .font(.body2).foregroundStyle(Color.textSecondary)
            }
        case .tooLittle:
            stepPage(pose: .anxious, title: "읽힌 시간이 너무 짧아요") {
                Text("하루의 10%(약 2시간 반)보다 적게 읽혀서 그래프를 만들 수 없어요. 센서가 끊긴 날이면 기록만 저장해도 오늘 칸은 채워져요.")
                    .font(.body2).foregroundStyle(Color.textSecondary)
            } actions: {
                PhotosPicker(selection: $pickerItem, matching: .screenshots) { Text("다른 스크린샷 고르기") }
                    .buttonStyle(.glubeePrimary)
                Button("오늘은 기록만 저장하기") { viewModel.saveRecordsOnly() }
                    .font(.body2).foregroundStyle(Color.textSecondary)
            }
        case .failed(let message):
            stepPage(pose: .sulky, title: "그래프 상태를 확인하지 못했어요") {
                Text(message).font(.body2).foregroundStyle(Color.textSecondary)
            } actions: {
                Button("다시 확인하기") {
                    viewModel.chooseAnotherScreenshot()
                    Task { await viewModel.refresh() }
                }
                .buttonStyle(.glubeePrimary)
            }
        }
    }

    private var dayWord: String {
        ReportDay.calendar.isDateInToday(viewModel.day) ? "오늘" : viewModel.dayTitle
    }

    private func upload(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        pickerItem = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let prepared = ImageResizer.prepareGraphForUpload(originalData: data) else { return }
        viewModel.uploadGraph(data: prepared.data, contentType: prepared.contentType)
    }

    // MARK: - ② 사진 확인

    private var photosStep: some View {
        let pending = viewModel.pendingPhotos
        return stepPage(pose: nil, title: "낮에 찍은 사진을\n확인해 주세요") {
            Text(pending.isEmpty ? "확인할 사진이 없어요." : "\(pending.count)개 남았어요. 누르면 음식 확인 화면이 열려요.")
                .font(.body2).foregroundStyle(Color.textSecondary)

            if case .loaded(let report, let points) = viewModel.report.state, !points.isEmpty {
                GlucoseDayChart(day: viewModel.day, points: points, episodes: report.episodes,
                                insulinEvents: report.insulinEvents ?? [])
                    .frame(height: 150)
            }

            VStack(spacing: 0) {
                ForEach(timeline) { row in
                    TimelineRow(row: row,
                                isUploading: viewModel.isUploadingPhotos,
                                onOpen: { if case .photo(let photo) = row.kind { path.append(photo) } },
                                onRetry: { Task { await viewModel.retryUploads() } },
                                onDiscard: { if case .photo(let photo) = row.kind { viewModel.discard(photo) } })
                    Divider()
                }
            }
        } actions: {
            Button("다음 · 인슐린 확인") { viewModel.goToInsulin() }
                .buttonStyle(pending.isEmpty ? .glubeePrimary : .glubeeMuted)
                .disabled(!pending.isEmpty)
        }
        .refreshable { await viewModel.refresh() }
    }

    /// 그날 기록을 시간순으로: 확인 대기 사진, 이미 저장된 식사·인슐린
    private var timeline: [TimelineItem] {
        var items = viewModel.pendingPhotos.map { TimelineItem(time: $0.capturedAt, kind: .photo($0)) }
        if case .loaded(let report, _) = viewModel.report.state {
            items += report.episodes.map {
                TimelineItem(time: $0.startAt, kind: .meal(context: $0.effectiveContext, count: $0.intakeCount))
            }
            items += (report.insulinEvents ?? []).map {
                TimelineItem(time: $0.occurredAt, kind: .insulin(kind: $0.kind, units: $0.units))
            }
        }
        return items.sorted { $0.time < $1.time }
    }

    // MARK: - ③ 인슐린

    private var insulinStep: some View {
        let events: [DailyReport.InsulinMarker] = {
            if case .loaded(let report, _) = viewModel.report.state { return report.insulinEvents ?? [] }
            return []
        }()
        return stepPage(pose: .note, title: "기록하지 않은 인슐린이\n있었나요?") {
            Text(events.isEmpty ? "오늘 남긴 인슐린 기록이 없어요." : "오늘 남긴 인슐린 기록이에요.")
                .font(.body2).foregroundStyle(Color.textSecondary)
            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                HStack {
                    Text(ReportDay.timeString(from: event.occurredAt)).font(.body2).foregroundStyle(Color.textSecondary)
                    Text("\(event.kind) · \(event.units.formatted(.number.precision(.fractionLength(0...1))))U")
                        .font(.body1).foregroundStyle(Color.textPrimary)
                    Spacer()
                }
                .card(.insulin, padding: Spacing.s)
            }
            HStack(spacing: Spacing.s) {
                Button { showInsulinRecord = true } label: { Label("인슐린 추가", systemImage: "syringe") }
                    .buttonStyle(.glubeeSecondary)
                Button { showFoodRecord = true } label: { Label("빠진 음식", systemImage: "fork.knife") }
                    .buttonStyle(.glubeeSecondary)
            }
        } actions: {
            Button("다 확인했어요") { Task { await viewModel.finish() } }
                .buttonStyle(viewModel.canFinish ? .glubeePrimary : .glubeeMuted)
                .disabled(!viewModel.canFinish)
            if !viewModel.pendingPhotos.isEmpty {
                Text("확인하지 않은 사진이 \(viewModel.pendingPhotos.count)장 있어요.")
                    .font(.caption1).foregroundStyle(Color.textSecondary)
            }
        }
    }

    // MARK: - 공통 틀

    /// 위에 큰 제목(+ 오른쪽 작은 글루비), 가운데 내용, 아래 버튼
    private func stepPage(
        pose: MascotPose?,
        title: String,
        centered: Bool = false,
        @ViewBuilder content: () -> some View,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: centered ? .center : .leading, spacing: Spacing.m) {
                    if centered, let pose {
                        MascotView(pose: pose, size: 140, floats: true).padding(.top, Spacing.xl)
                    }
                    HStack(alignment: .top) {
                        Text(title)
                            .font(.headline1)
                            .foregroundStyle(Color.textPrimary)
                            .multilineTextAlignment(centered ? .center : .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        if !centered, let pose {
                            Spacer(minLength: Spacing.s)
                            MascotView(pose: pose, size: 72)
                        }
                    }
                    content()
                }
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.m)
            }
            VStack(spacing: Spacing.xs) { actions() }
                .padding(.horizontal, Spacing.gutter)
                .padding(.bottom, Spacing.s)
        }
    }
}

// MARK: - 타임라인 한 줄

private struct TimelineItem: Identifiable {
    enum Kind {
        case photo(PendingPhoto)
        case meal(context: IntakeContext, count: Int)
        case insulin(kind: String, units: Double)
    }

    let time: Date
    let kind: Kind
    var id: String {
        switch kind {
        case .photo(let photo): "photo-\(photo.id)"
        case .meal: "meal-\(time.timeIntervalSince1970)"
        case .insulin: "insulin-\(time.timeIntervalSince1970)"
        }
    }
}

private struct TimelineRow: View {
    let row: TimelineItem
    let isUploading: Bool
    let onOpen: () -> Void
    let onRetry: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            Text(ReportDay.timeString(from: row.time))
                .font(.caption1).monospacedDigit()
                .foregroundStyle(Color.textSecondary)
                .frame(width: 44, alignment: .leading)
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body1).foregroundStyle(Color.textPrimary)
                Text(subtitle).font(.caption1).foregroundStyle(Color.textSecondary)
            }
            Spacer()
            trailing
        }
        .padding(.vertical, Spacing.s)
        .contentShape(Rectangle())
        .onTapGesture { if case .photo(let photo) = row.kind, photo.photoId != nil { onOpen() } }
        .contextMenu {
            if case .photo = row.kind {
                Button("이 사진 지우기", systemImage: "trash", role: .destructive, action: onDiscard)
            }
        }
    }

    private var title: String {
        switch row.kind {
        case .photo(let photo): "\(photo.context.displayName) 사진"
        case .meal(let context, let count): "\(context.displayName) 기록 · \(count)건"
        case .insulin(let kind, let units): "\(kind) · \(units.formatted(.number.precision(.fractionLength(0...1))))U"
        }
    }

    private var subtitle: String {
        switch row.kind {
        case .photo(let photo):
            if photo.photoId != nil { return "무엇인지 아직 몰라요" }
            if isUploading { return "올리는 중" }
            return photo.uploadFailed ? "올리지 못했어요" : "아직 올리지 않았어요"
        case .meal: return "확인함"
        case .insulin: return "투여 확인함"
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch row.kind {
        case .photo(let photo):
            if let image = UIImage(contentsOfFile: PendingPhotoStore.shared.imageURL(for: photo).path) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.field))
                    .accessibilityHidden(true)
            } else {
                iconBox("photo", fill: .brandSoft, tint: .onBrandSoft)
            }
        case .meal: iconBox("fork.knife", fill: .brandSoft, tint: .onBrandSoft)
        case .insulin: iconBox("syringe", fill: .insulinSoft, tint: .insulin)
        }
    }

    private func iconBox(_ name: String, fill: Color, tint: Color) -> some View {
        Image(systemName: name)
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(fill, in: RoundedRectangle(cornerRadius: Radius.field))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var trailing: some View {
        switch row.kind {
        case .photo(let photo):
            if photo.photoId != nil {
                Text("확인 필요")
                    .font(.caption1.weight(.semibold))
                    .foregroundStyle(Color.onBrandSoft)
                    .padding(.horizontal, Spacing.xs).padding(.vertical, Spacing.xxs)
                    .background(Color.brandSoft, in: Capsule())
            } else if isUploading {
                ProgressView()
            } else {
                Button("다시 시도", action: onRetry).font(.caption1)
            }
        case .meal, .insulin:
            Image(systemName: "checkmark").foregroundStyle(Color.mintStrong).accessibilityLabel("확인함")
        }
    }
}

// MARK: - ④ 완성

private struct DayCompleteView: View {
    let viewModel: DayCloseViewModel
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fill: CGFloat = 0
    /// 차오르는 연출이 끝나면 실제 칸 상태(기록만 저장한 날 표시 등)로 바꾼다
    @State private var filled = false
    @State private var streak = 0
    @State private var pose: MascotPose = .wave
    @State private var milestone: Int?

    var body: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            Text(viewModel.recordOnly ? "오늘 기록을 저장했어요" : "\(dayWord) 그래프가 완성됐어요")
                .font(.headline2)
                .foregroundStyle(Color.textSecondary)
            StreakNumber(value: streak)
            WeekHoneycomb(states: viewModel.weekStates(fillingToday: !filled),
                          animatingIndex: todayIndex, fillProgress: fill)
                .padding(.horizontal, Spacing.gutter)
            MascotView(pose: pose, size: 140, motion: pose == .happy ? .jump : .pop)
            Spacer()
            NavigationLink { DailyReportView(viewModel: viewModel.report) } label: { Text("하루 그래프 보기") }
                .buttonStyle(.glubeePrimary)
            Button("닫기", action: onClose)
                .font(.body2).foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.bottom, Spacing.s)
        .task { await play() }
        .sensoryFeedback(.success, trigger: streak)
        .fullScreenCover(item: Binding(get: { milestone.map(Milestone.init) }, set: { milestone = $0?.days })) { item in
            MilestoneCelebrationView(days: item.days) { milestone = nil }
        }
    }

    private struct Milestone: Identifiable {
        let days: Int
        var id: Int { days }
    }

    private var dayWord: String {
        ReportDay.calendar.isDateInToday(viewModel.day) ? "오늘" : viewModel.dayTitle
    }

    /// 이번 주 칸 중 마무리하는 날의 자리
    private var todayIndex: Int {
        (ReportDay.calendar.component(.weekday, from: viewModel.day) + 5) % 7
    }

    /// 오늘 칸 채우기 → 숫자 +1 → 기념일이면 축하 화면
    private func play() async {
        streak = viewModel.streakBefore
        guard !reduceMotion else {
            fill = 1
            filled = true
            streak = viewModel.streakAfter
            pose = .happy
            return
        }
        try? await Task.sleep(for: .milliseconds(400))
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 1.1)) { fill = 1 }
        try? await Task.sleep(for: .milliseconds(1100))
        filled = true
        withAnimation(.snappy) { streak = viewModel.streakAfter }
        pose = .happy
        if MilestoneCelebrationView.milestones.contains(viewModel.streakAfter) {
            try? await Task.sleep(for: .milliseconds(900))
            milestone = viewModel.streakAfter
        }
    }
}

/// "캡처하는 법 보기"
private struct CaptureHowToSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SheetHeader(title: "그래프 캡처하는 법", onClose: { dismiss() })
            ForEach(Array(["리브레 앱을 열고 \"오늘\" 일일 그래프 화면으로 가요.",
                           "그래프 전체(날짜·눈금 포함)가 화면에 다 보이게 해요.",
                           "측면 버튼 + 음량 높이기 버튼을 같이 눌러 화면을 캡처해요.",
                           "글루비로 돌아와 \"스크린샷 고르기\"에서 방금 찍은 화면을 골라요."].enumerated()), id: \.offset) { index, text in
                HStack(alignment: .top, spacing: Spacing.s) {
                    Text("\(index + 1)")
                        .font(.headline2)
                        .foregroundStyle(Color.onButton)
                        .frame(width: 28, height: 28)
                        .background(Color.buttonFill, in: Circle())
                    Text(text).font(.body1).foregroundStyle(Color.textPrimary)
                }
            }
            Spacer()
        }
        .padding(Spacing.gutter)
        .presentationDetents([.medium])
    }
}

#Preview {
    DayCloseView()
}
