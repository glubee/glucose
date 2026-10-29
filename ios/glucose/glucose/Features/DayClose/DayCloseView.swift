//
//  DayCloseView.swift
//  glucose
//
//  하루 마무리 "글루비와 쓰는 줄노트"(디자이너 시안 01~09).
//  시작 화면 → 줄 그은 한 장짜리 다이어리(그래프 붙이기 · 음식 시간줄 · 빠진 음식 · 투여 기록 · 한마디) → 벌집 한 칸.
//  위에는 "오늘의 다이어리" 진행 막대, 아래에는 "오늘 정리 마치기"(다 살펴봐야 켜진다).
//  글루비는 기록 행동에만 말한다. 실패 화면의 글루비는 웃지 않는다. 혈당 수치를 평가하지 않는다.
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
    @State private var path: [UUID] = []
    @State private var deletionCandidate: UUID?
    @State private var showsDeleteConfirm = false
    @State private var showsDeleteError = false
    @FocusState private var noteFocused: Bool

    init(day: Date? = nil, photoStore: PendingPhotoStore? = nil) {
        _viewModel = State(initialValue: DayCloseViewModel(day: day, photoStore: photoStore ?? .shared))
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                progressHeader
                Group {
                    if viewModel.isFinished {
                        DayCompleteView(viewModel: viewModel, onClose: { dismiss() })
                    } else if viewModel.started {
                        diary
                    } else {
                        intro
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .background(Color.canvas)
            .navigationTitle("하루 마무리")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.started && !viewModel.isFinished {
                        Button { withAnimation { viewModel.started = false } } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("처음으로")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .foregroundStyle(Color.textSecondary)
                        .accessibilityLabel("닫기")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                PendingPhotoDetailView(photoID: id, store: viewModel.photoStore) {
                    path.removeAll()
                    Task { await viewModel.refresh() }
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
        .sheet(isPresented: $showInsulinRecord, onDismiss: {
            viewModel.insulinAnswered = true
            Task { await viewModel.refresh() }
        }) { InsulinConfirmView() }
        .alert("이 사진을 지울까요?", isPresented: $showsDeleteConfirm, presenting: deletionCandidate) { id in
            Button("사진 지우기", role: .destructive) { showsDeleteError = !viewModel.photoStore.remove(id) }
            Button("취소", role: .cancel) {}
        } message: { _ in Text(PendingPhotoDeletion.message) }
        .alert(viewModel.photoStore.errorMessage ?? "사진을 지우지 못했어요.", isPresented: $showsDeleteError) {
            Button("확인", role: .cancel) {}
        }
        .onChange(of: viewModel.photoStore.photos.map(\.id)) { _, ids in path.removeAll { !ids.contains($0) } }
        .animation(.spring(duration: 0.35), value: viewModel.started)
        .animation(.spring(duration: 0.35), value: viewModel.isFinished)
        .animation(.spring(duration: 0.35), value: viewModel.foodsAnswered)
        .animation(.spring(duration: 0.35), value: viewModel.insulinAnswered)
    }

    // MARK: - 진행 막대

    private var progressHeader: some View {
        VStack(spacing: Spacing.xs) {
            HStack {
                Text("오늘의 다이어리").font(.body2).foregroundStyle(Color.textSecondary)
                Spacer()
                Text(viewModel.progressLabel).font(.body2.weight(.semibold)).foregroundStyle(Diary.ink)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.line.opacity(0.6))
                    Capsule().fill(Diary.ink).frame(width: max(6, geometry.size.width * viewModel.progress))
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.top, Spacing.xxs)
        .padding(.bottom, Spacing.s)
        .animation(.easeInOut(duration: 0.4), value: viewModel.progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("오늘의 다이어리, \(viewModel.progressLabel)")
        .accessibilityValue("\(Int(viewModel.progress * 100))%")
    }

    // MARK: - 01 시작

    private var intro: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Spacing.m) {
                    dateHeading
                    VStack(spacing: Spacing.xs) {
                        Text(nickname.isEmpty ? "오늘 하루는 어땠나요?" : "\(nickname)님, 오늘 하루는 어땠나요?")
                            .font(.headline1)
                            .foregroundStyle(Color.textPrimary)
                            .multilineTextAlignment(.center)
                        Text("오늘 남긴 기록을 보면서 이야기해봐요.")
                            .font(.body2).foregroundStyle(Color.textSecondary)
                    }
                    .padding(.top, Spacing.m)
                    introPhotos.padding(.vertical, Spacing.s)
                    MascotView(pose: .wave, size: 110, floats: true)
                    Text("빠진 기록은 더하고,\n남기고 싶은 이야기도 적어봐요.")
                        .font(.body1).foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.m)
            }
            .background(DiaryPaper())
            VStack(spacing: Spacing.xs) {
                Button("시작하기") { viewModel.started = true }
                    .buttonStyle(.glubeePrimary)
                    .accessibilityIdentifier("dayCloseStart")
                Text("나중에 이어서 할 수 있어요.").font(.caption1).foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.s)
        }
    }

    private var dateHeading: some View {
        VStack(spacing: Spacing.xxs) {
            Text(stamp)
                .font(.caption1.weight(.semibold).monospacedDigit())
                .foregroundStyle(Diary.ink)
                .padding(.horizontal, Spacing.xs).padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Diary.ink.opacity(0.5), lineWidth: 1))
                .rotationEffect(.degrees(-3))
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(longDate)
                .font(.pretendard(26, relativeTo: .title, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            Text("오늘의 조각을 함께 모아봐요.")
                .font(.body2).foregroundStyle(Color.textSecondary)
        }
    }

    /// 시작 화면의 사진 두 장(남긴 음식 사진 → 확인 대기 사진 순)
    @ViewBuilder
    private var introPhotos: some View {
        let saved = marks.compactMap(\.photoId).prefix(2)
        let pending = viewModel.pendingPhotos.prefix(2 - saved.count)
        if !saved.isEmpty || !pending.isEmpty {
            HStack(spacing: Spacing.m) {
                ForEach(Array(saved.enumerated()), id: \.offset) { index, id in
                    DiaryPolaroid { FoodPhotoThumbnail(photoId: id, size: 128, cornerRatio: 0.01) }
                        .rotationEffect(.degrees(index == 0 ? -3 : 2))
                }
                ForEach(Array(pending.enumerated()), id: \.element.id) { index, photo in
                    DiaryPolaroid { PendingPhotoThumbnail(photo: photo, store: viewModel.photoStore, size: 128, cornerRadius: 1) }
                        .rotationEffect(.degrees((saved.count + index) == 0 ? -3 : 2))
                }
            }
            .accessibilityHidden(true)
        }
    }

    // MARK: - 다이어리 한 장

    private var diary: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    graphSection
                    if viewModel.hasGraphOrRecordOnly {
                        foodTimeline
                        foodQuestion
                        if viewModel.foodsAnswered {
                            insulinSection
                        }
                        if viewModel.foodsAnswered && viewModel.insulinAnswered {
                            noteSection
                            if viewModel.canFinish {
                                DiaryTimeRow(time: nil) {
                                    VStack(alignment: .leading, spacing: Spacing.xs) {
                                        BeeSpeech(pose: .happy, text: "오늘 이야기를 함께 모았네요.")
                                        Text("남긴 기록은 언제든 다시 볼 수 있어요.")
                                            .font(.body2).foregroundStyle(Color.textSecondary)
                                            .padding(.leading, 56)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.bottom, Spacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await viewModel.refresh(); await viewModel.retryUploads() }
            .background(DiaryPaper())
            finishBar
        }
    }

    private var finishBar: some View {
        VStack(spacing: Spacing.xs) {
            Text(finishHint)
                .font(.caption1)
                .foregroundStyle(viewModel.canFinish ? Diary.ink : Color.textSecondary)
            Button("오늘 정리 마치기") { Task { await viewModel.finish() } }
                .buttonStyle(viewModel.canFinish ? .glubeePrimary : .glubeeMuted)
                .disabled(!viewModel.canFinish)
                .accessibilityIdentifier("dayCloseFinish")
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.top, Spacing.xs)
        .padding(.bottom, Spacing.s)
        .background(Color.canvas)
    }

    private var finishHint: String {
        if viewModel.canFinish { return "✓ 다 살펴봤어요. 편하게 마무리해요." }
        if viewModel.hasGraphOrRecordOnly, !viewModel.pendingPhotos.isEmpty {
            return "확인하지 않은 사진이 \(viewModel.pendingPhotos.count)장 있어요"
        }
        return "↓ 아래까지 함께 살펴봐요"
    }

    // MARK: 그래프 붙이기

    @ViewBuilder
    private var graphSection: some View {
        switch viewModel.graphPhase {
        case .checking:
            DiaryTimeRow(time: nil) { ProgressView().frame(maxWidth: .infinity).padding() }
        case .needsUpload, .otherDay:
            DiaryTimeRow(time: nil) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    BeeSpeech(pose: .photo, text: "\(dayWord) 리브레 그래프를 붙여볼까요?")
                    Text("리브레 앱 \"오늘\" 그래프 화면을 캡처해서 골라주세요.")
                        .font(.body2).foregroundStyle(Color.textSecondary)
                    if case .otherDay(let date) = viewModel.graphPhase {
                        Text("방금 올린 그래프는 \(date) 그래프였어요. \(viewModel.dayTitle) 그래프를 올려주세요.")
                            .font(.body2).foregroundStyle(Color.alert)
                    }
                    PhotosPicker(selection: $pickerItem, matching: .screenshots) {
                        Label("그래프 스크린샷 고르기", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.glubeePrimary)
                    HStack {
                        DiaryLink(title: "캡처하는 법 보기") { showHowTo = true }
                        Spacer()
                        DiaryLink(title: "그래프 없이 기록만") { viewModel.saveRecordsOnly() }
                    }
                }
            }
        case .uploading, .analyzing:
            DiaryTimeRow(time: nil) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    BeeSpeech(pose: .magnifier, text: "그래프를 읽고 있어요")
                    HStack(spacing: Spacing.xs) {
                        ProgressView()
                        Text("10초쯤 걸려요. 화면을 닫아도 계속 읽어요.")
                            .font(.body2).foregroundStyle(Color.textSecondary)
                    }
                }
            }
        case .ready(let coverage):
            DiaryTimeRow(time: nil) {
                DiaryNoteCard(tint: Diary.ink) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack {
                            Text("리브레 그래프 · 붙임").font(.body2.weight(.semibold)).foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text("하루의 \(Int((coverage * 100).rounded()))%")
                                .font(.caption1).foregroundStyle(Color.textSecondary)
                        }
                        if case .loaded(let report, let points) = viewModel.report.state, !points.isEmpty {
                            GlucoseDayChart(day: viewModel.day, points: points, episodes: report.episodes,
                                            insulinEvents: report.insulinEvents ?? [], height: 150)
                        }
                        PhotosPicker(selection: $pickerItem, matching: .screenshots) {
                            Text("다시 붙이기 ›").font(.body2).underline().foregroundStyle(Diary.ink)
                        }
                    }
                }
            }
        case .notRecognized:
            graphProblem(pose: .think, title: "그래프를 읽지 못했어요",
                         message: "리브레 앱의 \"오늘\" 그래프가 화면에 다 보이게 다시 캡처해 주세요. 잘리거나 가려지면 읽을 수 없어요.")
        case .tooLittle:
            graphProblem(pose: .anxious, title: "읽힌 시간이 너무 짧아요",
                         message: "하루의 10%(약 2시간 반)보다 적게 읽혀서 그래프를 만들 수 없어요. 센서가 끊긴 날이면 기록만 남겨도 오늘 칸은 채워져요.")
        case .failed(let message):
            DiaryTimeRow(time: nil) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    BeeSpeech(pose: .sulky, text: "그래프 상태를 확인하지 못했어요")
                    Text(message).font(.body2).foregroundStyle(Color.textSecondary)
                    Button("다시 확인하기") {
                        viewModel.chooseAnotherScreenshot()
                        Task { await viewModel.refresh() }
                    }
                    .buttonStyle(.glubeeSecondary)
                }
            }
        }
    }

    private func graphProblem(pose: MascotPose, title: String, message: String) -> some View {
        DiaryTimeRow(time: nil) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                BeeSpeech(pose: pose, text: title)
                Text(message).font(.body2).foregroundStyle(Color.textSecondary)
                PhotosPicker(selection: $pickerItem, matching: .screenshots) { Text("다른 스크린샷 고르기") }
                    .buttonStyle(.glubeePrimary)
                HStack {
                    DiaryLink(title: "캡처하는 법 보기") { showHowTo = true }
                    Spacer()
                    DiaryLink(title: "그래프 없이 기록만") { viewModel.saveRecordsOnly() }
                }
            }
        }
    }

    // MARK: 음식 시간줄

    private enum FoodRow: Identifiable {
        case saved(DailyReport.Episode.IntakeMark, index: Int)
        case pending(PendingPhoto)

        var id: String {
            switch self {
            case .saved(_, let index): "saved-\(index)"
            case .pending(let photo): "pending-\(photo.id)"
            }
        }
        var time: Date {
            switch self {
            case .saved(let mark, _): mark.occurredAt
            case .pending(let photo): photo.capturedAt
            }
        }
    }

    private var marks: [DailyReport.Episode.IntakeMark] {
        guard case .loaded(let report, _) = viewModel.report.state else { return [] }
        return report.episodes.flatMap(\.marks).sorted { $0.occurredAt < $1.occurredAt }
    }

    private var foodRows: [FoodRow] {
        (marks.enumerated().map { FoodRow.saved($1, index: $0) } + viewModel.pendingPhotos.map(FoodRow.pending))
            .sorted { $0.time < $1.time }
    }

    @ViewBuilder
    private var foodTimeline: some View {
        if foodRows.isEmpty {
            DiaryTimeRow(time: nil) {
                Text("오늘 남긴 음식 기록이 아직 없어요.")
                    .font(.body2).foregroundStyle(Color.textSecondary)
                    .padding(.vertical, Spacing.xs)
            }
        }
        ForEach(foodRows) { row in
            switch row {
            case .saved(let mark, _):
                DiaryTimeRow(time: mark.occurredAt, label: Diary.label(for: mark.occurredAt, context: mark.context)) {
                    savedFood(mark)
                }
            case .pending(let photo):
                DiaryTimeRow(time: photo.capturedAt, label: Diary.label(for: photo.capturedAt, context: photo.context)) {
                    pendingFood(photo)
                }
            }
        }
    }

    private func savedFood(_ mark: DailyReport.Episode.IntakeMark) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            if let photoId = mark.photoId {
                DiaryPolaroid(tint: mark.context.tint) {
                    FoodPhotoThumbnail(photoId: photoId, size: 112, cornerRatio: 0.01)
                }
                .padding(.top, Spacing.xxs)
            }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text((mark.foods ?? []).isEmpty ? mark.context.displayName : (mark.foods ?? []).joined(separator: " · "))
                    .font(.body1).foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("저장됨")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Diary.ink)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.mintSoft, in: Capsule())
            }
            .padding(.top, Spacing.xs)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func pendingFood(_ photo: PendingPhoto) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Button { path.append(photo.id) } label: {
                DiaryPolaroid(tint: photo.context.tint) {
                    PendingPhotoThumbnail(photo: photo, store: viewModel.photoStore, size: 112, cornerRadius: 1)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, Spacing.xxs)
            .accessibilityLabel("\(photo.context.chipName) 사진 확인하기")
            .accessibilityIdentifier("pendingPhotoOpen-\(photo.id.uuidString)")
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("\(photo.context.chipName) 사진").font(.body1).foregroundStyle(Color.textPrimary)
                Text("확인 필요")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.onBrandSoft)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.brandSoft, in: Capsule())
                Text(viewModel.photoStore.statusMessage(for: photo))
                    .font(.caption1).foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if photo.photoId != nil {
                    DiaryLink(title: "확인하기") { path.append(photo.id) }
                } else if !viewModel.isUploadingPhotos {
                    DiaryLink(title: "다시 올리기") { Task { await viewModel.retryUploads() } }
                }
                Button("지우기") { askToDelete(photo.id) }
                    .font(.caption1)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityLabel("이 사진 지우기")
                    .accessibilityIdentifier("pendingPhotoDelete-\(photo.id.uuidString)")
            }
            .padding(.top, Spacing.xs)
            Spacer(minLength: 0)
        }
    }

    private func askToDelete(_ id: UUID) {
        deletionCandidate = id
        showsDeleteConfirm = true
    }

    // MARK: 빠진 음식

    @ViewBuilder
    private var foodQuestion: some View {
        if viewModel.foodsAnswered {
            DiaryTimeRow(time: nil) {
                DiaryNoteCard {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("추가 음식 · 이게 전부예요").font(.body2.weight(.semibold)).foregroundStyle(Color.textPrimary)
                        DiaryLink(title: "수정") { viewModel.foodsAnswered = false; viewModel.insulinAnswered = false }
                    }
                }
            }
        } else if viewModel.pendingPhotos.isEmpty {
            DiaryTimeRow(time: nil) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    BeeSpeech(pose: .curious, text: marks.isEmpty ? "오늘 드신 걸 남겨볼까요?" : "이 밖에 드신 것도 있나요?")
                    Text("간식이나 음료도 남길 수 있어요.")
                        .font(.body2).foregroundStyle(Color.textSecondary)
                    Button { showFoodRecord = true } label: {
                        Label(marks.isEmpty ? "음식 기록하기" : "음식 더 남기기", systemImage: "camera")
                    }
                    .buttonStyle(.glubeePrimary)
                    Button(marks.isEmpty ? "먹은 게 없어요" : "이게 전부예요") { viewModel.foodsAnswered = true }
                        .buttonStyle(.glubeeSecondary)
                        .accessibilityIdentifier("dayCloseFoodsDone")
                }
            }
        } else {
            DiaryTimeRow(time: nil) {
                BeeSpeech(pose: .think, text: "위 사진을 먼저 확인해 줄래요?")
            }
        }
    }

    // MARK: 투여 기록

    private var insulinEvents: [DailyReport.InsulinMarker] {
        guard case .loaded(let report, _) = viewModel.report.state else { return [] }
        return (report.insulinEvents ?? []).sorted { $0.occurredAt < $1.occurredAt }
    }

    private var insulinGroups: [[DailyReport.InsulinMarker]] {
        var groups: [[DailyReport.InsulinMarker]] = []
        for event in insulinEvents {
            if let first = groups.last?.first, abs(event.occurredAt.timeIntervalSince(first.occurredAt)) <= 120 {
                groups[groups.count - 1].append(event)
            } else {
                groups.append([event])
            }
        }
        return groups
    }

    @ViewBuilder
    private var insulinSection: some View {
        // 같은 시각(2분 안)에 함께 맞은 인슐린은 한 카드로
        ForEach(Array(insulinGroups.enumerated()), id: \.offset) { _, group in
            DiaryTimeRow(time: group[0].occurredAt, label: group.count > 1 ? "인슐린 \(group.count)가지" : "인슐린") {
                DiaryNoteCard(tint: .insulin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.count > 1 ? "인슐린 함께 맞음 · 저장됨" : "인슐린 기록 · 저장됨")
                            .font(.body2.weight(.semibold)).foregroundStyle(Color.textPrimary)
                        ForEach(Array(group.enumerated()), id: \.offset) { _, event in
                            Text("\(event.kind) · \(event.units.formatted(.number.precision(.fractionLength(0...1))))U")
                                .font(.body2).foregroundStyle(Color.textSecondary)
                        }
                        Text("실제 투여 \(ReportDay.timeString(from: group[0].occurredAt))")
                            .font(.caption1).foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        if viewModel.insulinAnswered {
            DiaryTimeRow(time: nil) {
                DiaryNoteCard {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("투여 기록 · 확인했어요").font(.body2.weight(.semibold)).foregroundStyle(Color.textPrimary)
                        DiaryLink(title: "더 기록하기") { showInsulinRecord = true }
                    }
                }
            }
        } else {
            DiaryTimeRow(time: nil) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    BeeSpeech(pose: .note, text: "기록하지 않은 투여가 있었나요?")
                    Text(insulinEvents.isEmpty ? "오늘 남긴 인슐린 기록은 없네요." : "오늘 남긴 인슐린 기록은 위에 있어요.")
                        .font(.body2).foregroundStyle(Color.textSecondary)
                    Button("인슐린 기록하기") { showInsulinRecord = true }
                        .buttonStyle(.glubeePrimary)
                    Button(insulinEvents.isEmpty ? "없어요" : "이게 전부예요") { viewModel.insulinAnswered = true }
                        .buttonStyle(.glubeeSecondary)
                        .accessibilityIdentifier("dayCloseInsulinDone")
                }
            }
        }
    }

    // MARK: 한마디

    private var noteSection: some View {
        DiaryTimeRow(time: nil) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Label("오늘에 남길 한마디", systemImage: "pencil")
                        .font(.headline2).foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text("선택").font(.caption1).foregroundStyle(Color.textSecondary)
                }
                TextField("기억해두고 싶은 일이 있나요?", text: $viewModel.note, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($noteFocused)
                    .font(.body1)
                    .padding(Spacing.s)
                    .background(Color.canvas, in: RoundedRectangle(cornerRadius: Radius.field))
                    .overlay(RoundedRectangle(cornerRadius: Radius.field).strokeBorder(Diary.ink.opacity(0.35), lineWidth: 1))
                Text("한마디는 이 기기에만 남아요.").font(.caption1).foregroundStyle(Color.textSecondary)
            }
        }
    }

    // MARK: - 공통

    private var nickname: String { UserPreferences.shared.nickname }

    private var dayWord: String {
        ReportDay.calendar.isDateInToday(viewModel.day) ? "오늘" : viewModel.dayTitle
    }

    private var longDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = ReportDay.calendar.timeZone
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter.string(from: viewModel.day)
    }

    private var stamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = ReportDay.calendar.timeZone
        formatter.dateFormat = "MM.dd · EEE"
        return formatter.string(from: viewModel.day).uppercased()
    }

    private func upload(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        pickerItem = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let prepared = ImageResizer.prepareGraphForUpload(originalData: data) else { return }
        viewModel.uploadGraph(data: prepared.data, contentType: prepared.contentType)
    }
}

// MARK: - 09 완성 · 벌집 한 칸

private struct DayCompleteView: View {
    let viewModel: DayCloseViewModel
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fill: CGFloat = 0
    /// 차오르는 연출이 끝나면 실제 칸 상태(기록만 저장한 날 표시 등)로 바꾼다
    @State private var filled = false
    @State private var milestone: Int?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    BeeSpeech(pose: filled ? .happy : .wave,
                              text: nickname.isEmpty ? "함께 돌아봐줘서 고마워요." : "함께 돌아봐줘서\n고마워요, \(nickname)님.")
                    VStack(spacing: Spacing.s) {
                        Text("오늘의 한 칸을 남겼어요")
                            .font(.headline1).foregroundStyle(Color.textPrimary)
                        WeekHoneycomb(states: viewModel.weekStates(fillingToday: !filled),
                                      animatingIndex: todayIndex, fillProgress: fill)
                        Text(streakCaption)
                            .font(.caption1).foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Spacing.s)

                    storyCard
                    Text("기록이 없는 날도 함께 돌아보면 한 칸이 남아요.")
                        .font(.caption1).foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.m)
            }
            .background(DiaryPaper())
            VStack(spacing: Spacing.xxs) {
                Button("다이어리 닫기") {
                    if MilestoneCelebrationView.milestones.contains(viewModel.streakAfter) {
                        milestone = viewModel.streakAfter
                    } else {
                        onClose()
                    }
                }
                .buttonStyle(.glubeeSecondary)
                .accessibilityIdentifier("dayCloseDone")
                NavigationLink { DailyReportView(viewModel: viewModel.report) } label: {
                    Text("하루 그래프 보기 ›").font(.body2).underline().foregroundStyle(Diary.ink)
                }
                .frame(minHeight: Metrics.minTapTarget)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.s)
        }
        .task { await play() }
        .sensoryFeedback(.success, trigger: filled)
        .fullScreenCover(item: Binding(get: { milestone.map(Milestone.init) }, set: { milestone = $0?.days })) { item in
            MilestoneCelebrationView(days: item.days, earnedHoneypot: item.days % DayCloseStore.daysPerHoneypot == 0) {
                milestone = nil
                onClose()
            }
        }
    }

    /// 오늘 남긴 이야기: 식사 때, 투여 기록(내가 남긴 값 그대로), 한마디
    private var storyCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("오늘 남긴 이야기").font(.headline2).foregroundStyle(Color.textPrimary)
            storyLine("식사 기록", mealSummary)
            storyLine("투여 기록", insulinSummary)
            storyLine("한마디", viewModel.note.isEmpty ? "—" : viewModel.note)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.m)
        .background(Color.canvas, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Diary.ink.opacity(0.3), lineWidth: 1))
    }

    private func storyLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text(title).font(.body2).foregroundStyle(Color.textSecondary)
            Text("·").foregroundStyle(Color.textSecondary)
            Text(value).font(.body2).foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var mealSummary: String {
        guard case .loaded(let report, _) = viewModel.report.state else { return "—" }
        var labels: [String] = []
        for mark in report.episodes.flatMap(\.marks).sorted(by: { $0.occurredAt < $1.occurredAt }) {
            let label = Diary.label(for: mark.occurredAt, context: mark.context)
            if !labels.contains(label) { labels.append(label) }
        }
        return labels.isEmpty ? "—" : labels.joined(separator: ", ")
    }

    private var insulinSummary: String {
        guard case .loaded(let report, _) = viewModel.report.state, let events = report.insulinEvents, !events.isEmpty else { return "—" }
        return events.sorted { $0.occurredAt < $1.occurredAt }.map {
            "\($0.units.formatted(.number.precision(.fractionLength(0...1))))U \(ReportDay.timeString(from: $0.occurredAt))"
        }.joined(separator: ", ")
    }

    private struct Milestone: Identifiable {
        let days: Int
        var id: Int { days }
    }

    private var nickname: String { UserPreferences.shared.nickname }

    private var streakCaption: String {
        let streak = filled ? viewModel.streakAfter : viewModel.streakBefore
        return streak > 0 ? "\(shortDate) · 하루 마무리 · 연속 \(streak)일" : "\(shortDate) · 하루 마무리"
    }

    private var shortDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = ReportDay.calendar.timeZone
        formatter.dateFormat = "M월 d일"
        return formatter.string(from: viewModel.day)
    }

    /// 이번 주 칸 중 마무리하는 날의 자리
    private var todayIndex: Int {
        (ReportDay.calendar.component(.weekday, from: viewModel.day) + 5) % 7
    }

    /// 오늘 칸 채우기 → 연속 숫자 +1
    private func play() async {
        guard !reduceMotion else {
            fill = 1
            filled = true
            return
        }
        try? await Task.sleep(for: .milliseconds(400))
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 1.1)) { fill = 1 }
        try? await Task.sleep(for: .milliseconds(1100))
        withAnimation(.snappy) { filled = true }
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
                           "글루비로 돌아와 \"그래프 스크린샷 고르기\"에서 방금 찍은 화면을 골라요."].enumerated()), id: \.offset) { index, text in
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
