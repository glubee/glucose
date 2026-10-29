#if DEBUG
import SwiftUI
import UIKit

/// 실제 사용자 저장소와 분리된 도형 사진으로 목록·삭제·촬영 완료를 확인한다.
struct DebugPhotoFlow: View {
    enum Mode { case pending, dayClose, quick }
    let mode: Mode
    @State private var showsSheet = true
    @State private var store: PendingPhotoStore?
    @State private var quickModel: QuickCaptureViewModel?

    var body: some View {
        RootTabView()
            .sheet(isPresented: $showsSheet) {
                if let store {
                    switch mode {
                    case .pending: PendingPhotosView(store: store)
                    case .dayClose: DayCloseView(day: .now, photoStore: store)
                    case .quick:
                        if let quickModel { QuickCaptureView(viewModel: quickModel) }
                    }
                } else { ProgressView() }
            }
            .task {
                guard store == nil else { return }
                let sampleStore = DebugPhotoSamples.makeStore()
                store = sampleStore
                if mode == .quick {
                    let model = QuickCaptureViewModel(store: sampleStore)
                    model.capture(DebugPhotoSamples.image())
                    quickModel = model
                }
            }
    }
}

private enum DebugPhotoSamples {
    static func image(_ foods: [String] = ["현미밥", "계란말이"]) -> UIImage {
        DemoFoodArt.image(foods: foods)
    }

    static func makeStore() -> PendingPhotoStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GlubeePhotoPreview-\(UUID())")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let photos = [
            PendingPhoto(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                         capturedAt: .now, context: .meal, photoId: UUID()),
            PendingPhoto(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                         capturedAt: .now.addingTimeInterval(-600), context: .snack, uploadFailed: true),
            PendingPhoto(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                         capturedAt: .now.addingTimeInterval(-1200), context: .meal)
        ]
        // 사진마다 상황에 맞는 음식 그림(식사 · 간식 · 식사)
        let foods = [["김치찌개", "현미밥"], ["바나나"], ["샌드위치", "아메리카노"]]
        for (photo, names) in zip(photos, foods) {
            if let data = image(names).jpegData(compressionQuality: 0.8) {
                try? data.write(to: directory.appendingPathComponent(photo.fileName))
            }
        }
        if let index = try? JSONEncoder().encode(photos) {
            try? index.write(to: directory.appendingPathComponent("index.json"))
        }
        return PendingPhotoStore(directory: directory, isAuthenticated: { false }, onActivity: { _ in })
    }
}
#endif
