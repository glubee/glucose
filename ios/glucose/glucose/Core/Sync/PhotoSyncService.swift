import Foundation

struct SyncedPhoto: Codable, Equatable {
    let photoId: UUID
    let clientId: UUID?
    let capturedAt: Date
    let context: IntakeContext
    let status: String
    let confirmed: Bool
    let dismissed: Bool
}
struct PhotoSyncPage: Decodable { let items: [SyncedPhoto]; let nextCursor: String? }
struct PhotoMetadataUpdate: Encodable { let capturedAt: Date; let clientId: UUID; let context: IntakeContext }

@MainActor
protocol PhotoSyncServing {
    func pendingPage(cursor: String?) async throws -> PhotoSyncPage
    func metadata(_ id: UUID) async throws -> SyncedPhoto
    func updateMetadata(_ id: UUID, value: PhotoMetadataUpdate) async throws
    func dismiss(_ id: UUID) async throws
}
@MainActor
struct PhotoSyncService: PhotoSyncServing {
    var sessionGeneration: UUID? = nil
    func pendingPage(cursor: String?) async throws -> PhotoSyncPage {
        var query = [URLQueryItem(name: "unconfirmed", value: "true"), URLQueryItem(name: "limit", value: "100")]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await APIClient.shared.send(path: "/v1/photos", queryItems: query, expectedSession: sessionGeneration)
    }
    func metadata(_ id: UUID) async throws -> SyncedPhoto { try await APIClient.shared.send(path: "/v1/photos/\(id.uuidString)", expectedSession: sessionGeneration) }
    func updateMetadata(_ id: UUID, value: PhotoMetadataUpdate) async throws {
        try await APIClient.shared.sendVoid(path: "/v1/photos/\(id.uuidString)/metadata", method: .patch, body: value, expectedSession: sessionGeneration)
    }
    func dismiss(_ id: UUID) async throws { try await APIClient.shared.sendVoid(path: "/v1/photos/\(id.uuidString)/dismiss", method: .post, expectedSession: sessionGeneration) }
}
