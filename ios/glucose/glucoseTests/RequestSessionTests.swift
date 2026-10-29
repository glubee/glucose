import XCTest
@testable import glucose

@MainActor
final class RequestSessionTests: XCTestCase {
    func testExplicitExpiredSessionCannotStartEvenAPublicRequest() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionURLProtocol.self]
        let client = APIClient(baseURL: URL(string: "https://sync.invalid")!, session: URLSession(configuration: configuration))
        SessionURLProtocol.starts = 0
        struct Response: Decodable { let ok: Bool }
        do {
            let _: Response = try await client.send(path: "/test", authenticated: false, expectedSession: UUID())
            XCTFail("an old session must be rejected before transport")
        } catch is CancellationError {} catch { XCTFail("expected cancellation, got a different failure") }
        XCTAssertEqual(SessionURLProtocol.starts, 0)
    }
}

private final class SessionURLProtocol: URLProtocol {
    nonisolated(unsafe) static var starts = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.starts += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"ok\":true}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
