import SwiftUI

struct BackupSettingsSection: View {
    @State private var model: BackupSettingsModel
    @State private var showsImport = false
    init(model: BackupSettingsModel? = nil) { _model = State(initialValue: model ?? .shared) }

    var body: some View {
        Section {
            HStack(spacing: Spacing.s) {
                if model.isWorking { ProgressView().accessibilityLabel("백업 중") }
                else { Image(systemName: model.coordinator.status == .saved ? "checkmark.icloud" : "icloud.and.arrow.up") }
                Text(model.headline).font(.body2).accessibilityIdentifier("backupStatus")
            }
            if model.hasPending {
                Text("하루 마무리의 변경 사항과 아직 올리지 못한 사진은 이 기기에 남아 있어요.")
                    .font(.caption1).foregroundStyle(Color.textSecondary)
            }
            Button("다시 시도") { Task { await model.retry() } }
                .disabled(!model.canSync || model.isWorking)
                .accessibilityIdentifier("backupRetry")
            if model.hasLegacy {
                Button("이전 기기 기록 가져오기") { showsImport = true }
                    .disabled(!model.canSync || model.isWorking)
                    .accessibilityIdentifier("backupImportLegacy")
            }
            if let message = model.importMessage {
                Text(message).font(.caption1).foregroundStyle(Color.textSecondary)
            }
        } header: {
            Text("기록 백업")
        } footer: {
            Text("하루 마무리 상태와 업로드된 대기 사진을 같은 계정에서 이어볼 수 있어요. 업로드 전 사진은 이 기기에만 남아 앱을 삭제하면 복원할 수 없어요. 이름·평소 인슐린 설정은 기기에 저장돼요.")
        }
        .alert("이전 자료를 현재 계정으로 가져올까요?", isPresented: $showsImport) {
            Button("이 계정으로 가져오기") { model.importLegacy() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 기기에 남아 있는 예전 자료가 본인의 기록인지 확인해 주세요. 다른 사람의 자료라면 가져오지 마세요.")
        }
    }
}
