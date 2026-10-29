//
//  PhotoCaptureView.swift
//  glucose
//
//  음식 사진 기록(v5): 상황 칩 → 사진(찍기·앨범) → 올리기 → 인식 결과 확인.
//  사진이 없을 때는 카메라 든 글루비가 빈 자리를 채운다. 양이나 처치 방법은 권하지 않는다.
//

import PhotosUI
import SwiftUI

struct PhotoCaptureView: View {
    @State private var viewModel = PhotoCaptureViewModel()
    @State private var uploadViewModel = PhotoUploadViewModel()
    @State private var showCamera = false
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var showRecognitionResult = false
    @Environment(\.dismiss) private var dismiss
    /// 음식 기록 시트에서 "찍기"로 열면 카메라를 바로 띄운다
    private let opensCamera: Bool

    init(context: IntakeContext = .meal, opensCamera: Bool = false) {
        let viewModel = PhotoCaptureViewModel()
        viewModel.context = context
        _viewModel = State(initialValue: viewModel)
        self.opensCamera = opensCamera
    }

    private var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.l) {
                        contextSection
                        photoSection.disabled(isUploadInFlight)
                        if let errorMessage = viewModel.errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.circle")
                                .font(.body2)
                                .foregroundStyle(Color.alert)
                        }
                    }
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.vertical, Spacing.m)
                }
                bottomBar
            }
            .background(Color.canvas)
            .navigationTitle("음식 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                        .disabled(isUploadInFlight)
                }
            }
            .onAppear {
                if opensCamera && isCameraAvailable && viewModel.previewImage == nil { showCamera = true }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView { image in
                    showCamera = false
                    guard !isUploadInFlight else { return }
                    uploadViewModel.reset()
                    viewModel.process(image)
                }
                .ignoresSafeArea()
            }
            .onChange(of: photosPickerItem) { _, newItem in
                Task { await loadPickedImage(newItem) }
            }
            .onChange(of: uploadViewModel.state) { _, newState in
                if newState == .done {
                    showRecognitionResult = true
                }
            }
            .navigationDestination(isPresented: $showRecognitionResult) {
                if let photoId = uploadViewModel.photoId {
                    RecognitionResultView(photoId: photoId, context: viewModel.context) {
                        dismiss()
                    }
                }
            }
            .interactiveDismissDisabled(isUploadInFlight)
        }
    }

    // MARK: - 상황

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "언제 먹었나요?")
            ChipPicker(options: IntakeContext.allCases.map { ($0, $0.chipTitle) }, selection: $viewModel.context)
                .disabled(isUploadInFlight)
            if viewModel.context == .hypoTreatment {
                Text("저혈당 대응으로 먹은 것만 찍어주세요.")
                    .font(.caption1)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    // MARK: - 사진

    @ViewBuilder
    private var photoSection: some View {
        if let previewImage = viewModel.previewImage {
            VStack(spacing: Spacing.s) {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sheet))
                    .accessibilityLabel("고른 음식 사진")
                if !isUploadInFlight && uploadViewModel.state != .done {
                    HStack(spacing: Spacing.xs) {
                        if isCameraAvailable {
                            Button { showCamera = true } label: { Label("다시 찍기", systemImage: "camera") }
                                .buttonStyle(.glubeeSecondary)
                        }
                        PhotosPicker(selection: $photosPickerItem, matching: .images) {
                            Label("다른 사진", systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(.glubeeSecondary)
                    }
                }
            }
        } else {
            VStack(spacing: Spacing.m) {
                MascotView(pose: .camera, size: 120, motion: .pop)
                VStack(spacing: Spacing.xxs) {
                    Text("먹은 음식을 찍어주세요")
                        .font(.headline2)
                        .foregroundStyle(Color.textPrimary)
                    Text("음식이 화면 가운데 오게 찍으면 더 잘 알아봐요.")
                        .font(.body2)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: Spacing.xs) {
                    if isCameraAvailable {
                        Button { showCamera = true } label: { Label("찍기", systemImage: "camera.fill") }
                            .buttonStyle(.glubeeAccent)
                    }
                    PhotosPicker(selection: $photosPickerItem, matching: .images) {
                        Label("앨범에서 고르기", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.glubeeSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.l)
            .padding(.horizontal, Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: Radius.sheet)
                    .strokeBorder(Color.line, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            )
        }
    }

    // MARK: - 아래 버튼

    @ViewBuilder
    private var bottomBar: some View {
        if viewModel.isReadyForUpload {
            VStack(spacing: Spacing.xs) {
                switch uploadViewModel.state {
                case .idle:
                    Button("올리고 음식 확인하기", action: startUpload)
                        .buttonStyle(.glubeePrimary)
                case .failed(let message):
                    Text(message)
                        .font(.caption1)
                        .foregroundStyle(Color.alert)
                    Button("다시 올리기", action: startUpload)
                        .buttonStyle(.glubeePrimary)
                case .starting, .completing:
                    progressRow(title: "사진을 올리는 중이에요", progress: nil)
                case .uploading(let progress):
                    progressRow(title: "사진을 올리는 중이에요", progress: progress)
                case .done:
                    Button("음식 확인하기") { showRecognitionResult = true }
                        .buttonStyle(.glubeePrimary)
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.s)
            .background(Color.canvas)
        }
    }

    private func progressRow(title: String, progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.body2.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            if let progress {
                ProgressView(value: progress).tint(Color.brand)
            } else {
                ProgressView().tint(Color.brand).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minHeight: Metrics.buttonHeight)
        .card(.brand, padding: Spacing.s)
    }

    private var isUploadInFlight: Bool {
        switch uploadViewModel.state {
        case .starting, .uploading, .completing: true
        default: false
        }
    }

    private func loadPickedImage(_ item: PhotosPickerItem?) async {
        guard let item, !isUploadInFlight else { return }
        photosPickerItem = nil
        let selectionID = viewModel.beginSelection()
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                viewModel.setError("사진을 불러오지 못했어요.")
                return
            }
            guard !isUploadInFlight else { return }
            if viewModel.process(image, selectionID: selectionID) { uploadViewModel.reset() }
        } catch {
            viewModel.setError("사진을 불러오지 못했어요.")
        }
    }

    private func startUpload() {
        guard let data = viewModel.processedData else { return }
        viewModel.invalidateSelection()
        let context = viewModel.context
        Task { await uploadViewModel.upload(imageData: data, context: context) }
    }
}

private extension IntakeContext {
    /// 칩에는 v5 표현을 쓴다(저장 값은 그대로)
    var chipTitle: String {
        switch self {
        case .meal: "식사"
        case .snack: "간식"
        case .hypoTreatment: "저혈당 대응"
        case .alcohol: "술"
        }
    }
}

#Preview {
    PhotoCaptureView()
}
