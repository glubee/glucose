import SwiftUI

struct ReportPhotoGallery: View {
    let group: ChartPhotoGroup
    var onChanged: () async -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text("사진 \(group.members.count)장").font(.headline2)
                    #if DEBUG
                    if ReportSamples.isEnabled {
                        Text("미리보기예요. 예시 사진과 기록은 고치거나 저장할 수 없어요.")
                            .font(.caption1).foregroundStyle(Color.textSecondary)
                    }
                    #endif
                    ForEach(Array(group.members.enumerated()), id: \.element.id) { index, member in
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            Text("\(ReportDay.timeString(from: member.mark.occurredAt)) · \(member.mark.context.displayName)")
                                .font(.headline2)
                            if let photoId = member.mark.photoId {
                                NavigationLink {
                                    ReportFullPhotoView(photoId: photoId)
                                } label: {
                                    ReportPhotoImage(photoId: photoId).frame(height: 240)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("사진 더 크게 보기")
                            }
                            Text((member.mark.foods ?? []).joined(separator: ", "))
                                .font(.body1).foregroundStyle(Color.textPrimary)
                            NavigationLink {
                                ReportRecordDestination(member: member, onChanged: onChanged)
                            } label: {
                                Label("기록 자세히 보기", systemImage: "doc.text.magnifyingglass")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.glubeeSecondary)
                            .accessibilityIdentifier("photoRecordDetail-\(index)")
                        }
                        .card()
                    }
                }
                .padding(Spacing.gutter)
            }
            .background(Color.canvas)
            .navigationTitle("사진 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() }.accessibilityIdentifier("closePhotoGallery") }
            }
        }
    }
}

private struct ReportRecordDestination: View {
    let member: ChartPhotoMember
    let onChanged: () async -> Void
    @State private var resolution: ReportRecordResolver.Resolution?
    @State private var failed = false
    @State private var attempt = 0
    @State private var showRecords = false

    private var allowsEditing: Bool {
        #if DEBUG
        return !ReportSamples.isEnabled
        #else
        return true
        #endif
    }

    var body: some View {
        Group {
            if case .found(let record) = resolution {
                RecordDetailView(item: .intake(record), allowsEditing: allowsEditing, onChanged: onChanged)
            } else if resolution != nil || failed {
                VStack(spacing: Spacing.m) {
                    Text(message).font(.body1).multilineTextAlignment(.center)
                    Button("다시 확인") { attempt += 1 }.buttonStyle(.glubeeSecondary)
                    if allowsEditing {
                        Button("전체 기록에서 찾기") { showRecords = true }.buttonStyle(.glubeeSecondary)
                    }
                }
                .padding(Spacing.gutter)
            } else {
                ProgressView("기록을 확인하고 있어요")
            }
        }
        .navigationTitle("기록 상세")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showRecords) { RecordsView() }
        .task(id: attempt) {
            resolution = nil
            failed = false
            #if DEBUG
            if ReportSamples.isEnabled {
                resolution = ReportSamples.record(for: member.mark).map(ReportRecordResolver.Resolution.found) ?? .missing
                return
            }
            #endif
            do {
                let result = try await ReportRecordResolver().resolve(mark: member.mark)
                guard !Task.isCancelled else { return }
                resolution = result
            } catch {
                guard !Task.isCancelled else { return }
                failed = true
            }
        }
    }

    private var message: String {
        if failed { return "기록을 불러오지 못했어요. 다시 시도해 주세요." }
        switch resolution {
        case .ambiguous: return "같은 시각의 기록이 여러 개예요. 전체 기록에서 확인해 주세요."
        case .missing: return "이 사진과 일치하는 기록을 찾지 못했어요. 기록이 바뀌거나 지워졌을 수 있어요."
        default: return "기록을 확인하지 못했어요. 전체 기록에서 찾아 주세요."
        }
    }
}

private struct ReportFullPhotoView: View {
    let photoId: UUID
    var body: some View {
        GeometryReader { geometry in
            ReportPhotoImage(photoId: photoId)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color.canvas)
        .navigationTitle("음식 사진")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 원래 비율을 유지해 사진 전체를 보여준다. 서명 주소가 만료되면 다시 받을 수 있다.
private struct ReportPhotoImage: View {
    let photoId: UUID
    @State private var url: URL?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        Group {
            #if DEBUG
            if let image = ReportSamples.image(for: photoId) {
                Image(uiImage: image).resizable().scaledToFit()
            } else { remoteImage }
            #else
            remoteImage
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: 12))
        .task(id: attempt) {
            url = nil
            failed = false
            #if DEBUG
            if ReportSamples.isEnabled { return }
            #endif
            let loaded = await PhotoViewURLCache.shared.url(for: photoId)
            guard !Task.isCancelled else { return }
            url = loaded
            failed = loaded == nil
        }
    }

    @ViewBuilder private var remoteImage: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFit()
                case .failure: retry
                default: ProgressView()
                }
            }
            .id(attempt)
        } else if failed { retry }
        else { ProgressView() }
    }

    private var retry: some View {
        VStack(spacing: Spacing.s) {
            Text("사진을 불러오지 못했어요").font(.body2)
            Button("다시 불러오기") {
                PhotoViewURLCache.shared.invalidate(photoId)
                attempt += 1
            }
        }
    }
}
