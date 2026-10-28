//
//  SettingsViewModel.swift
//  glucose
//

import Foundation

@Observable
final class SettingsViewModel {

    private(set) var isDeleting = false
    private(set) var errorMessage: String?

    func signOut() {
        AuthSession.shared.signOut()
    }

    func deleteAccount() async -> Bool {
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }

        do {
            try await APIClient.shared.sendVoid(path: "/v1/me", method: .delete)
            AuthSession.shared.signOut()
            await LocalDataEraser.eraseAll()
            return true
        } catch {
            errorMessage = "계정을 지우지 못했어요. 다시 시도해 주세요."
            return false
        }
    }
}
