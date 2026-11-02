import Foundation
import SimctlShared
import XCTest
@testable import Simctl

private final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            XCTFail("Missing mock response")
            return
        }
        let (status, data) = handler(request)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
            XCTFail("Invalid mock response")
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    static func body(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    override func stopLoading() { }
}

final class ClientTests: XCTestCase {
    private let device = UUID()
    private var sessions: [URLSession] = []

    override func tearDown() {
        sessions.forEach { $0.invalidateAndCancel() }
        sessions = []
        StubProtocol.handler = nil
        super.tearDown()
    }

    private func client(port: UInt16 = 18089) -> SimctlClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: configuration)
        sessions.append(session)
        let env = SimulatorEnvironment(host: .localhost(port: port), bundleIdentifier: "dev.test", deviceUdid: device)
        return SimctlClient(environment: env, session: session)
    }

    private func expectSuccess(_ invoke: (@escaping SimctlClient.DataTaskCallback) -> Void) {
        let done = expectation(description: "request")
        invoke { result in
            if case let .failure(error) = result { XCTFail(error.localizedDescription) }
            done.fulfill()
        }
        waitForExpectations(timeout: 3)
    }

    func testInstallUsesPathHeader() {
        let client = self.client()
        StubProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "path"), "/tmp/App With Spaces.app")
            XCTAssertNil(request.value(forHTTPHeaderField: "target_bundle_identifier"))
            return (200, Data())
        }
        expectSuccess { client.installApp("/tmp/App With Spaces.app", $0) }
    }

    func testDefaultContainerEncodesAppInsteadOfNull() {
        let client = self.client()
        StubProtocol.handler = { request in
            let decoded = try? JSONDecoder().decode(AppContainer.self, from: StubProtocol.body(request))
            guard case .app? = decoded else { XCTFail("Default must encode .app"); return (400, Data()) }
            return (200, Data())
        }
        expectSuccess { client.getAppContainer(completion: $0) }
    }

    func testClientsRetainIndependentHosts() {
        let first = client(port: 18089)
        let second = client(port: 18090)
        var ports: [Int] = []
        StubProtocol.handler = { request in
            ports.append(request.url?.port ?? 0)
            return (200, Data())
        }
        expectSuccess { first.getAppContainer(.app, completion: $0) }
        expectSuccess { second.getAppContainer(.app, completion: $0) }
        expectSuccess { first.getAppContainer(.data, completion: $0) }
        XCTAssertEqual(ports, [18089, 18090, 18089])
    }

    func testServerErrorRetainsBodyAndLocalizedMessage() {
        let client = self.client()
        let body = Data("TCC.db not found".utf8)
        StubProtocol.handler = { _ in (400, body) }
        let done = expectation(description: "error")
        client.getAppContainer { result in
            guard case let .failure(error) = result else { XCTFail("Expected failure"); done.fulfill(); return }
            XCTAssertEqual(error.responseBody, body)
            XCTAssertEqual(error.localizedDescription, "HTTP 400: TCC.db not found")
            done.fulfill()
        }
        waitForExpectations(timeout: 3)
    }

    func testMediaLibraryWireValue() {
        XCTAssertEqual(PrivacyService.media.rawValue, "media-library")
    }

    func testPhotosAddWireValue() {
        XCTAssertEqual(PrivacyService.photosAdd.rawValue, "photos-add")
    }
}
