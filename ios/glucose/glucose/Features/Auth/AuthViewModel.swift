//
//  AuthViewModel.swift
//  glucose
//

import AuthenticationServices
import Foundation
import Security

@Observable
final class AuthViewModel {

    private(set) var errorMessage: String?
    private(set) var isLoading = false

    /// Apple에 보내는 값과 서버에 보내는 값이 같은 원문이어야 한다 (서버가 해시 없이 그대로 비교한다).
    private(set) var currentNonce: String = AuthViewModel.randomNonceString()

    func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Apple 로그인 정보를 읽지 못했어요."
                return
            }
            let nonce = currentNonce
            Task { await signIn(identityToken: identityToken, nonce: nonce) }
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            errorMessage = "Apple 로그인을 마치지 못했어요. 다시 시도해 주세요."
        }
    }

    private func signIn(identityToken: String, nonce: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let started = AuthSession.shared.generation
        do {
            let tokens: AuthTokens = try await APIClient.shared.send(
                path: "/v1/auth/apple",
                method: .post,
                body: AppleLoginRequest(identityToken: identityToken, nonce: nonce),
                authenticated: false, expectedSession: started
            )
            guard AuthSession.shared.generation == started else { return }
            AuthSession.shared.signIn(with: tokens)
            currentNonce = AuthViewModel.randomNonceString()
        } catch {
            errorMessage = "로그인하지 못했어요. 잠시 후 다시 시도해 주세요."
        }
    }

    private static func randomNonceString(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randomBytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            precondition(status == errSecSuccess, "난수 생성에 실패했습니다: \(status)")

            for byte in randomBytes where remainingLength > 0 {
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }
}
