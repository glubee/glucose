//
//  AuthSession.swift
//  glucose
//
//  로그인 상태의 단일 소스. 토큰은 Keychain에만 저장하고, 앱 어디서든 이걸 통해서만 읽는다.
//

import Foundation

@MainActor
@Observable
final class AuthSession {

    static let shared = AuthSession()

    private let keychain = KeychainStore()
    private let accessTokenKey = "access_token"
    private let refreshTokenKey = "refresh_token"

    private(set) var accountID: UUID?
    private(set) var generation = UUID()
    private let legacyOwner: UUID?
    private var didBootstrap = false
    private(set) var accessToken: String?
    private(set) var isAuthenticated: Bool

    private init() {
        let token = keychain.get(accessTokenKey)
        accountID = token.flatMap(AccountIdentity.userID)
        legacyOwner = LegacyDataOwnership.initialOwner(in: .standard, cachedAccount: token.flatMap(AccountIdentity.userID))
        accessToken = token
        isAuthenticated = token != nil
    }

    func credential(for expected: UUID?) throws -> String {
        guard expected == generation else { throw CancellationError() }
        guard let accessToken else { throw APIError.notAuthenticated }
        return accessToken
    }

    func invalidatePendingRequests() { generation = UUID() }

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        AccountDataCoordinator.activate(accountID, allowLegacy: accountID != nil && accountID == legacyOwner)
    }

    func signIn(with tokens: AuthTokens) {
        store(tokens)
    }

    func signOut() {
        generation = UUID()
        AccountDataCoordinator.activate(nil)
        accountID = nil
        keychain.delete(accessTokenKey)
        keychain.delete(refreshTokenKey)
        accessToken = nil
        isAuthenticated = false
    }

    /// access 토큰 만료(401) 시 1회 시도한다. 성공하면 true.
    func refreshAccessToken() async -> Bool {
        guard let refreshToken = keychain.get(refreshTokenKey) else { return false }
        let started = generation
        do {
            let tokens: AuthTokens = try await APIClient.shared.send(
                path: "/v1/auth/refresh",
                method: .post,
                body: RefreshRequest(refreshToken: refreshToken),
                authenticated: false, expectedSession: started
            )
            guard generation == started,
                  AccountIdentity.userID(in: tokens.accessToken) == accountID else { return false }
            store(tokens)
            return true
        } catch {
            return false
        }
    }

    private func store(_ tokens: AuthTokens) {
        let owner = AccountIdentity.userID(in: tokens.accessToken)
        if owner != accountID || !isAuthenticated {
            generation = UUID()
            AccountDataCoordinator.activate(owner)
            accountID = owner
        }
        keychain.set(tokens.accessToken, for: accessTokenKey)
        keychain.set(tokens.refreshToken, for: refreshTokenKey)
        accessToken = tokens.accessToken
        isAuthenticated = true
    }
}
