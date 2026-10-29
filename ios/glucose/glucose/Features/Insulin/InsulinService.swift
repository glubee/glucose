import Foundation

@MainActor
protocol InsulinServing {
    func create(_ request: InsulinEventRequest) async throws -> InsulinEventResponse
    func update(id: UUID, request: InsulinEventRequest) async throws -> InsulinEventResponse
    func delete(id: UUID) async throws
}

@MainActor
struct InsulinService: InsulinServing {
    func create(_ request: InsulinEventRequest) async throws -> InsulinEventResponse {
        try await APIClient.shared.send(path: "/v1/insulin-events", method: .post, body: request)
    }
    func update(id: UUID, request: InsulinEventRequest) async throws -> InsulinEventResponse {
        try await APIClient.shared.send(path: "/v1/insulin-events/\(id)", method: .patch, body: request)
    }
    func delete(id: UUID) async throws {
        try await APIClient.shared.sendVoid(path: "/v1/insulin-events/\(id)", method: .delete)
    }
}
