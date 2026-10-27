//
//  DayCloseView.swift
//  glucose
//
//  하루 마무리 화면. ① 리브레 그래프 ② 낮에 찍은 사진 확인 ③ 빠진 기록 추가 → 오늘 정리 마치기.
//  디자이너 시안(v4 하루 마무리 다이어리)이 나오면 맞춰 다듬는다.
//

import SwiftUI

struct DayCloseView: View {
    @State private var viewModel: DayCloseViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showGraphUpload = false
    @State private var showFoodRecord = false
    @State private var showInsulinRecord = false
    @State private var path: [PendingPhoto] = []

    init(day: Date? = nil) {
        _viewModel = State(initialValue: DayCloseViewModel(day: day))
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if viewModel.isFinished {
                    finishedView
                } else {
                    checklist
                }
            }
            .background(Color.canvas)
            .navigationTitle("하루 마무리")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .navigationDestination(for: PendingPhoto.self) { photo in
                if let photoId = photo.photoId {
                    RecognitionResultView(photoId: photoId, context: photo.context, occurredAt: photo.capturedAt) {
                        viewModel.confirmed(photo)
                        path.removeAll()
                    }
                }
            }
        }
        .task { await viewModel.refreshGraph() }
        .sheet(isPresented: $showGraphUpload) {
            GraphUploadView { _ in Task { await viewModel.refreshGraph() } }
        }
        .sheet(isPresented: $showFoodRecord) { PhotoCaptureView() }
        .sheet(isPresented: $showInsulinRecord) { InsulinConfirmView() }
    }

    // MARK: - 할 일

    private var checklist: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(viewModel.dayTitle)
                            .font(.body2)
                            .foregroundStyle(Color.textSecondary)
                        BeeSpeech(pose: viewModel.isGraphReady ? .nod : .clock, text: viewModel.beeLine)
                    }

                    graphSection
                    photosSection
                    missingSection
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.m)
            }
            .refreshable { await viewModel.refreshGraph() }

            VStack(spacing: Spacing.xs) {
                Button("오늘 정리 마치기") { Task { await viewModel.finish() } }
                    .buttonStyle(viewModel.canFinish ? .glubeePrimary : .glubeeMuted)
                    .disabled(!viewModel.canFinish)
                if let hint = viewModel.remainingHint {
                    Text(hint).font(.caption1).foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.s)
        }
    }

    private var graphSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(label: "1", title: "리브레 그래프")
            HStack(spacing: Spacing.s) {
                Image(systemName: viewModel.isGraphReady ? "checkmark.circle.fill" : "chart.xyaxis.line")
                    .font(.title2)
                    .foregroundStyle(viewModel.isGraphReady ? Color.mintStrong : Color.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(graphTitle).font(.headline2).foregroundStyle(Color.textPrimary)
                    Text(graphDetail).font(.body2).foregroundStyle(Color.textSecondary)
                }
                Spacer()
            }
            .card()

            if viewModel.graph != .checking {
                Button(viewModel.isGraphReady ? "다시 올리기" : "그래프 올리기") { showGraphUpload = true }
                    .buttonStyle(viewModel.isGraphReady ? .glubeeSecondary : .glubeePrimary)
            }
        }
    }

    private var graphTitle: String {
        switch viewModel.graph {
        case .checking: "확인하는 중…"
        case .missing: "아직 올린 그래프가 없어요"
        case .ready: "그래프를 읽었어요"
        case .failed: "상태를 확인하지 못했어요"
        }
    }

    private var graphDetail: String {
        switch viewModel.graph {
        case .checking: " "
        case .missing: "리브레 앱 → 일일 그래프 → 이미지로 저장한 뒤 올려주세요."
        case .ready(let coverage): "하루의 \(Int((coverage * 100).rounded()))%를 읽었어요. 아침에 다시 올리면 덮어써요."
        case .failed(let message): message
        }
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(label: "2", title: "낮에 찍은 사진",
                          trailing: viewModel.pendingPhotos.isEmpty ? nil : "\(viewModel.pendingPhotos.count)장")
            if viewModel.pendingPhotos.isEmpty {
                Text("확인할 사진이 없어요.")
                    .font(.body2)
                    .foregroundStyle(Color.textSecondary)
                    .card()
            } else {
                ForEach(viewModel.pendingPhotos) { photo in
                    PendingPhotoRow(photo: photo,
                                    isUploading: viewModel.isUploading,
                                    onOpen: { path.append(photo) },
                                    onRetry: { Task { await viewModel.retryUploads() } },
                                    onDiscard: { viewModel.discard(photo) })
                }
            }
        }
    }

    private var missingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(label: "3", title: "빠진 기록", subtitle: "사진을 못 찍은 식사나 기록 못 한 인슐린이 있나요?")
            HStack(spacing: Spacing.s) {
                Button { showFoodRecord = true } label: {
                    Label("음식 추가", systemImage: "fork.knife")
                }
                .buttonStyle(.glubeeSecondary)
                Button { showInsulinRecord = true } label: {
                    Label("인슐린 추가", systemImage: "syringe")
                }
                .buttonStyle(.glubeeSecondary)
            }
        }
    }

    // MARK: - 완성

    private var finishedView: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            MascotView(pose: .celebrate, size: 180)
            Text("오늘의 한 칸을 남겼어요.")
                .font(.headline1)
                .foregroundStyle(Color.textPrimary)
            Text(viewModel.dayTitle)
                .font(.body2)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            NavigationLink {
                DailyReportView(viewModel: DailyReportViewModel(day: viewModel.day))
            } label: {
                Text("완성된 하루 그래프 보기")
            }
            .buttonStyle(.glubeePrimary)
            Button("닫기") { dismiss() }
                .buttonStyle(.glubeeSecondary)
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.bottom, Spacing.s)
        .sensoryFeedback(.success, trigger: viewModel.isFinished)
    }
}

private struct PendingPhotoRow: View {
    let photo: PendingPhoto
    let isUploading: Bool
    let onOpen: () -> Void
    let onRetry: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(ReportDay.timeString(from: photo.capturedAt) + " · " + photo.context.displayName)
                    .font(.headline2)
                    .foregroundStyle(Color.textPrimary)
                Text(status)
                    .font(.body2)
                    .foregroundStyle(photo.uploadFailed ? Color.alert : Color.textSecondary)
            }
            Spacer()
            if photo.photoId != nil {
                Button("확인", action: onOpen).buttonStyle(.borderedProminent).tint(Color.mintStrong)
            } else if isUploading {
                ProgressView()
            } else {
                Button("다시 시도", action: onRetry).buttonStyle(.bordered)
            }
        }
        .card()
        .contextMenu {
            Button("이 사진 지우기", systemImage: "trash", role: .destructive, action: onDiscard)
        }
    }

    private var status: String {
        if photo.photoId != nil { return "글루비가 음식을 살펴봤어요" }
        if isUploading { return "올리는 중" }
        return photo.uploadFailed ? "올리지 못했어요" : "아직 올리지 않았어요"
    }

    @ViewBuilder
    private var thumbnail: some View {
        let url = PendingPhotoStore.shared.imageURL(for: photo)
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: Radius.field))
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: Radius.field)
                .fill(Color.surfaceMuted)
                .frame(width: 56, height: 56)
        }
    }
}

#Preview {
    DayCloseView()
}
