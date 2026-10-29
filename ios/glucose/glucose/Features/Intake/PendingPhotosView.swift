import SwiftUI

struct PendingPhotosView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [UUID] = []
    @State private var deletionCandidate: UUID?
    @State private var showsDeleteConfirm = false
    @State private var showsDeleteError = false
    private let store: PendingPhotoStore

    init(store: PendingPhotoStore? = nil) { self.store = store ?? .shared }

    private var photos: [PendingPhoto] { store.photos.sorted { $0.capturedAt > $1.capturedAt } }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if photos.isEmpty {
                    StateView(kind: .empty, title: "확인할 사진이 없어요",
                              message: "위젯으로 찍은 사진은 여기와 하루 마무리에서 확인해요.")
                } else {
                    List {
                        Text("사진을 눌러 확인해 주세요. 옆 버튼이나 왼쪽으로 밀어서 지울 수 있어요.")
                            .font(.body2).foregroundStyle(Color.textSecondary)
                            .listRowSeparator(.hidden).listRowBackground(Color.clear)
                        ForEach(photos) { photo in
                            PendingPhotoRow(photo: photo, store: store,
                                            onOpen: { path.append(photo.id) }, onDelete: { askToDelete(photo.id) })
                                .listRowSeparator(.hidden).listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 6, leading: Spacing.gutter, bottom: 6, trailing: Spacing.gutter))
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button { askToDelete(photo.id) } label: { Label("지우기", systemImage: "trash") }
                                        .tint(Color.alert).accessibilityLabel("밀어서 사진 지우기")
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable { await store.uploadPending() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.canvas)
            .navigationTitle("확인 안 한 사진")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
            }
            .navigationDestination(for: UUID.self) { id in
                PendingPhotoDetailView(photoID: id, store: store) { path.removeAll() }
            }
            .alert("이 사진을 지울까요?", isPresented: $showsDeleteConfirm,
                                presenting: deletionCandidate) { id in
                Button("사진 지우기", role: .destructive) { showsDeleteError = !store.remove(id) }
                Button("취소", role: .cancel) {}
            } message: { _ in Text(PendingPhotoDeletion.message) }
            .alert(store.errorMessage ?? "사진을 지우지 못했어요.", isPresented: $showsDeleteError) {
                Button("확인", role: .cancel) {}
            }
            .onChange(of: photos.map(\.id)) { _, ids in path.removeAll { !ids.contains($0) } }
            .task { await store.uploadPending() }
        }
    }

    private func askToDelete(_ id: UUID) {
        deletionCandidate = id
        showsDeleteConfirm = true
    }
}

#Preview { PendingPhotosView() }
