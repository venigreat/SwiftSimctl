import Foundation
import SimctlShared
import Swifter
import XCTest
@testable import SimctlServerCore

final class ServerTests: XCTestCase {
    private let device = UUID()

    private func request(_ path: ServerPath, method: String = "GET", bundle: String? = "dev.test") -> HttpRequest {
        let request = HttpRequest()
        request.method = method
        request.path = path.rawValue
        request.headers = ["device_udid": device.uuidString]
        request.headers["bundle_identifier"] = bundle
        return request
    }

    private func dispatch(_ request: HttpRequest, server: SimctlServer) -> HttpResponse {
        server.server.dispatch(request).1(request)
    }

    func testServerDefaultsToLoopback() {
        let server = SimctlServer()
        XCTAssertEqual(server.server.listenAddressIPv4, "127.0.0.1")
        XCTAssertEqual(server.server.listenAddressIPv6, "::1")
    }

    func testNullContainerAcceptedForOldClients() {
        let server = SimctlServer()
        var invoked = false
        server.onGetAppContainer { device, bundle, container in
            XCTAssertEqual(device, self.device)
            XCTAssertEqual(bundle, "dev.test")
            if case .app = container { invoked = true }
            return .success("app-path")
        }
        let request = self.request(.getAppContainer, method: "POST")
        request.body = Array("null".utf8)
        XCTAssertEqual(dispatch(request, server: server).statusCode, 200)
        XCTAssertTrue(invoked)
    }

    func testPrivacyResetAllowsMissingBundleButGrantDoesNot() {
        let server = SimctlServer()
        var invoked = false
        server.onPrivacy { _, bundle, action, service in
            XCTAssertNil(bundle)
            XCTAssertEqual(action, .reset)
            XCTAssertEqual(service, .camera)
            invoked = true
            return .success("")
        }
        let request = self.request(.privacy, bundle: nil)
        request.headers["privacy_action"] = "reset"
        request.headers["privacy_service"] = "camera"
        XCTAssertEqual(dispatch(request, server: server).statusCode, 200)
        XCTAssertTrue(invoked)
        request.headers["privacy_action"] = "grant"
        XCTAssertEqual(dispatch(request, server: server).statusCode, 400)
    }

    func testInstallAcceptsCorrectAndLegacyHeaders() {
        let server = SimctlServer()
        var received: [String] = []
        server.onInstallApp { _, _, path in received.append(path); return .success("") }
        for header in ["path", "target_bundle_identifier"] {
            let request = self.request(.installApp)
            request.headers[header] = "/tmp/App With Spaces.app"
            XCTAssertEqual(dispatch(request, server: server).statusCode, 200)
        }
        XCTAssertEqual(received, Array(repeating: "/tmp/App With Spaces.app", count: 2))
    }

    func testLegacyMediaHeaderMapsToSupportedService() {
        let server = SimctlServer()
        server.onPrivacy { _, _, _, service in
            XCTAssertEqual(service.rawValue, "media-library")
            return .success("")
        }
        let request = self.request(.privacy)
        request.headers["privacy_action"] = "grant"
        request.headers["privacy_service"] = "media"
        XCTAssertEqual(dispatch(request, server: server).statusCode, 200)
    }

    func testFailuresRemainHTTPFailures() {
        let server = SimctlServer()
        server.onPrivacy { _, _, _, _ in .failure(CommandError("TCC.db not found")) }
        let request = self.request(.privacy)
        request.headers["privacy_action"] = "grant"
        request.headers["privacy_service"] = "userTracking"
        XCTAssertEqual(dispatch(request, server: server).statusCode, 400)
    }
}
