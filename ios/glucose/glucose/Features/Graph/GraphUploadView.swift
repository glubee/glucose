//
//  GraphUploadView.swift
//  glucose
//
//  혈당 가져오기(v5): 리브레 일일 그래프 이미지 여러 장을 한 번에 고르고 올린다. 한 장 = 하루치 혈당.
//  날짜는 서버가 이미지에서 읽는다. 앨범에서만 고른다(화면을 카메라로 다시 찍으면 격자·눈금 인식이 잘 안 된다).
//

import PhotosUI
import SwiftUI

struct GraphUploadView: View {
    @State private var uploader = GraphBatchUploader()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isLoadingPicks = false
    @Environment(\.dismiss) private var dismiss

    private let onUploaded: (String) -> Void
    private static let maxSelection = 40

    init(onUploaded: @escaping (String) -> Void = { _ in }) {
        self.onUploaded = onUploaded
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.l) {
                        if uploader.items.isEmpty {
                            emptyState
                        } else {
                            summary
                            itemList
                        }
                    }
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.vertical, Spacing.m)
                }
                if !uploader.items.isEmpty {
                    bottomBar
                }
            }
            .background(Color.canvas)
            .navigationTitle("혈당 가져오기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                        .disabled(uploader.isRunning)
                }
            }
            .onChange(of: pickerItems) { _, items in
                Task { await loadPicked(items) }
            }
            .interactiveDismissDisabled(uploader.isRunning)
            #if DEBUG
            .onAppear(perform: addDebugSamples)
            #endif
        }
    }

    // MARK: - 비어 있을 때

    private var emptyState: some View {
        VStack(spacing: Spacing.m) {
            MascotView(pose: .calendar, size: 120, motion: .pop)
            VStack(spacing: Spacing.xxs) {
                Text("리브레 그래프를 골라주세요")
                    .font(.headline2)
                    .foregroundStyle(Color.textPrimary)
                Text("리브레 앱 → 일일 그래프 → 공유 → 이미지 저장으로\n저장한 그래프예요. 한 장이 하루예요.")
                    .font(.body2)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            picker(title: "앨범에서 고르기", style: .accent)
            Text("한 번에 \(Self.maxSelection)장까지 고를 수 있어요. 날짜는 그래프에서 읽어요.")
                .font(.caption1)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.l)
        .padding(.horizontal, Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: Radius.sheet)
                .strokeBorder(Color.line, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
    }

    // MARK: - 요약

    private var summary: some View {
        let total = uploader.items.count
        return VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(uploader.doneCount)")
                    .font(.bigNumber)
                    .foregroundStyle(Color.textPrimary)
                Text("/ \(total)장 반영")
                    .font(.headline2)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                if isLoadingPicks { ProgressView() }
            }
            ProgressView(value: Double(uploader.finishedCount), total: Double(max(total, 1)))
                .tint(Color.brand)
            if uploader.failedCount > 0 {
                Text("\(uploader.failedCount)장은 올리지 못했어요. 아래에서 이유를 보고 다시 시도할 수 있어요.")
                    .font(.caption1)
                    .foregroundStyle(Color.alert)
            }
            if !uploader.duplicateDates.isEmpty {
                Text("같은 날짜 그래프가 여러 장이에요: \(uploader.duplicateDates.map(ReportDay.displayString(fromAPIString:)).joined(separator: ", ")). 나중에 끝난 장으로 바뀌어요.")
                    .font(.caption1)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .card(.brand)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 목록

    private var itemList: some View {
        VStack(spacing: Spacing.xs) {
            ForEach(sortedItems) { item in
                GraphBatchRow(item: item)
            }
        }
    }

    /// 끝난 장은 날짜순, 진행 중·실패는 뒤에
    private var sortedItems: [GraphBatchItem] {
        let done = uploader.items.filter { $0.resultDate != nil }.sorted { ($0.resultDate ?? "") < ($1.resultDate ?? "") }
        return done + uploader.items.filter { $0.resultDate == nil }
    }

    // MARK: - 아래 버튼

    private var bottomBar: some View {
        VStack(spacing: Spacing.xs) {
            if uploader.isRunning {
                Text("올리는 동안 앱을 닫지 말아주세요")
                    .font(.caption1)
                    .foregroundStyle(Color.textSecondary)
                Button {} label: { ProgressView().tint(Color.onButton) }
                    .buttonStyle(.glubeePrimary)
                    .disabled(true)
            } else if hasPending {
                Button(uploader.failedCount > 0 && !hasIdle ? "실패한 \(uploader.failedCount)장 다시 시도" : "\(pendingCount)장 올리기") {
                    Task { await runUpload() }
                }
                .buttonStyle(.glubeePrimary)
                picker(title: "더 고르기", style: .secondary)
            } else {
                Button("다 됐어요") { dismiss() }
                    .buttonStyle(.glubeePrimary)
                picker(title: "더 고르기", style: .secondary)
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, Spacing.s)
        .background(Color.canvas)
    }

    private var hasIdle: Bool { uploader.items.contains { $0.data != nil && $0.state == .idle } }
    private var pendingCount: Int {
        uploader.items.filter { item in
            guard item.data != nil else { return false }
            if case .idle = item.state { return true }
            if case .failed = item.state { return true }
            return false
        }.count
    }
    private var hasPending: Bool { pendingCount > 0 }

    private enum PickerStyle { case accent, secondary }

    @ViewBuilder
    private func picker(title: String, style: PickerStyle) -> some View {
        let label = PhotosPicker(selection: $pickerItems, maxSelectionCount: Self.maxSelection,
                                 selectionBehavior: .ordered, matching: .images) {
            Label(title, systemImage: "photo.on.rectangle")
        }
        .disabled(uploader.isRunning || isLoadingPicks)
        switch style {
        case .accent: label.buttonStyle(.glubeeAccent)
        case .secondary: label.buttonStyle(.glubeeSecondary)
        }
    }

    // MARK: - 동작

    private func loadPicked(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isLoadingPicks = true
        var datas: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) { datas.append(data) }
        }
        uploader.add(originalData: datas)
        pickerItems = []
        isLoadingPicks = false
    }

    private func runUpload() async {
        let before = Set(uploader.items.compactMap(\.resultDate))
        await uploader.run()
        for date in Set(uploader.items.compactMap(\.resultDate)).subtracting(before).sorted() {
            onUploaded(date)
        }
    }

    #if DEBUG
    /// 실행 인자 -graphUpload: 로그인 없이 이 화면 보기(-graphUploadSample: 예시 이미지 4장, 올리지는 않음)
    private func addDebugSamples() {
        guard ProcessInfo.processInfo.arguments.contains("-graphUploadSample"), uploader.items.isEmpty else { return }
        let colors: [UIColor] = [.systemBlue, .systemTeal, .systemIndigo, .systemGray]
        let datas = colors.compactMap { color in
            UIGraphicsImageRenderer(size: CGSize(width: 120, height: 200)).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 120, height: 200))
            }.pngData()
        }
        uploader.add(originalData: datas)
    }
    #endif
}

private struct GraphBatchRow: View {
    let item: GraphBatchItem

    var body: some View {
        HStack(spacing: Spacing.s) {
            Group {
                if let thumbnail = item.thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                } else {
                    Color.surfaceMuted
                }
            }
            .frame(width: 44, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline2)
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle)
                    .font(.caption1)
                    .foregroundStyle(isFailed ? Color.alert : Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            trailing
        }
        .card(padding: Spacing.s)
        .accessibilityElement(children: .combine)
    }

    private var isFailed: Bool {
        if case .failed = item.state { return true }
        return false
    }

    private var title: String {
        switch item.state {
        case .done(let date, _): ReportDay.displayString(fromAPIString: date)
        case .failed: "올리지 못했어요"
        case .idle: "올릴 준비"
        case .uploading: "올리는 중"
        case .analyzing: "그래프 읽는 중"
        }
    }

    private var subtitle: String {
        switch item.state {
        case .done(_, let coverage): "하루의 \(Int((coverage * 100).rounded()))%를 읽었어요"
        case .failed(let message): message
        case .idle: "아래 버튼을 누르면 올려요"
        case .uploading, .analyzing: "날짜는 그래프에서 읽어요"
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch item.state {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.mintStrong)
                .accessibilityLabel("반영됨")
        case .uploading, .analyzing:
            ProgressView()
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.alert)
                .accessibilityHidden(true)
        case .idle:
            EmptyView()
        }
    }
}

#Preview {
    GraphUploadView()
}
