import Foundation

@MainActor
protocol IntakeServing {
    func get(id: UUID) async throws -> IntakeResponse
    func create(_ request: CreateIntakeRequest) async throws -> IntakeResponse
    func update(id: UUID, request: CreateIntakeRequest) async throws -> IntakeResponse
    func delete(id: UUID) async throws
    func recognize(photoId: UUID) async throws -> RecognitionResponse
}

@MainActor
struct IntakeService: IntakeServing {
    func get(id: UUID) async throws -> IntakeResponse {
        try await APIClient.shared.send(path: "/v1/intakes/\(id.uuidString)")
    }

    func create(_ request: CreateIntakeRequest) async throws -> IntakeResponse {
        try await APIClient.shared.send(path: "/v1/intakes", method: .post, body: request)
    }

    func update(id: UUID, request: CreateIntakeRequest) async throws -> IntakeResponse {
        try await APIClient.shared.send(path: "/v1/intakes/\(id.uuidString)", method: .patch, body: request)
    }

    func delete(id: UUID) async throws {
        try await APIClient.shared.sendVoid(path: "/v1/intakes/\(id.uuidString)", method: .delete)
    }

    func recognize(photoId: UUID) async throws -> RecognitionResponse {
        try await APIClient.shared.send(path: "/v1/photos/\(photoId.uuidString)/recognition")
    }
}
