import SwiftUI

/// 원래 비율을 유지해 사진 전체를 보여준다. 서명 주소가 만료되면 다시 받을 수 있다.
struct StoredPhotoImage: View {
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
