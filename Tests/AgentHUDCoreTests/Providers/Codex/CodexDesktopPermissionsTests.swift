import AgentHUDSupport
import Darwin
import Foundation
import XCTest
@testable import AgentHUDCore

final class CodexDesktopPermissionsTests: XCTestCase, @unchecked Sendable {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let threadID = "native-thread"

    private func wire(id: JSONValue = .string("native-request"), threadID: String = "native-thread",
                      persist: JSONValue = .array([.string("session"), .string("always")]),
                      completed: Bool = false) -> JSONValue {
        .object([
            "id": id, "method": .string("mcpServer/elicitation/request"), "completed": .bool(completed),
            "params": .object([
                "threadId": .string(threadID), "turnId": .string("native-turn"), "mode": .string("form"),
                "serverName": .string("cua_repl"), "message": .string("Allow Computer Use to use \"Agent HUD\"?"),
                "requestedSchema": .object(["type": .string("object"), "properties": .object([:])]),
                "_meta": .object([
                    "codex_approval_kind": .string("mcp_tool_call"), "connector_id": .string("computer-use"),
                    "connector_name": .string("Computer Use"), "persist": persist,
                    "tool_name": .string("get_app_state"), "tool_params": .object(["app": .string("com.agenthud.app")]),
                    "tool_params_display": .array([.object([
                        "name": .string("app"), "display_name": .string("App"), "value": .string("Agent HUD"),
                    ])]),
                ]),
            ]),
        ])
    }

    private func state(_ requests: [JSONValue]) -> JSONValue {
        .object(["id": .string(threadID), "cwd": .string("/Users/me/project"), "requests": .array(requests)])
    }

    private func pending(_ wire: JSONValue? = nil) throws -> CodexDesktopPermissions.Pending {
        try XCTUnwrap(CodexDesktopPermissions.pending(state([wire ?? self.wire()]), threadID: threadID,
            ownerClientID: "desktop-owner", now: now).first)
    }

    private func replacing(_ value: JSONValue, at path: [String], with replacement: JSONValue) -> JSONValue {
        guard let key = path.first, var object = value.objectValue else { return value }
        object[key] = path.count == 1 ? replacement : replacing(object[key] ?? .null, at: Array(path.dropFirst()), with: replacement)
        return .object(object)
    }

    func testScreenshotRequestCarriesAppContextAndExactlyTheAdvertisedScopes() throws {
        let item = try pending()
        XCTAssertEqual(item.request.source, .codex)
        XCTAssertEqual(item.request.vendor, "Codex")
        XCTAssertEqual(item.request.sessionID, threadID)
        XCTAssertEqual(item.request.toolName, "computer_use_app")
        XCTAssertTrue(item.request.summary.contains("Agent HUD"))
        XCTAssertEqual(item.request.detail, "com.agenthud.app")
        XCTAssertEqual(item.request.cwd, "/Users/me/project")
        XCTAssertEqual(item.request.at, now)
        XCTAssertEqual(item.request.nativeApproval, .computerUseApp(persist: ["session", "always"]))
        XCTAssertEqual(item.request.alwaysAllow, .object(["persist": .string("always")]))
        XCTAssertEqual(item.wireRequest, wire())
        XCTAssertEqual(item.requestID, .string("native-request"))
        XCTAssertEqual(PermissionDecision.allow.response(for: item.request), PermissionDecision.noDecision)
    }

    func testCompletedUnrelatedAndMalformedRequestsAreExcluded() throws {
        let unrelated: [JSONValue] = [
            wire(completed: true), wire(threadID: "other-thread"),
            wire(persist: .array([.string("always")])), wire(persist: .array([.string("session"), .string("unknown")])),
            wire(persist: .array([.string("session"), .integer(2)])), wire(persist: .null),
            wire(id: .bool(true)), wire(id: .number(1.5)), wire(id: .null), wire(id: .string("")),
            replacing(wire(), at: ["method"], with: .string("item/permissions/requestApproval")),
            replacing(wire(), at: ["params", "mode"], with: .string("url")),
            replacing(wire(), at: ["params", "_meta", "connector_id"], with: .string("browser-use")),
            replacing(wire(), at: ["params", "_meta", "codex_approval_kind"], with: .string("tool_suggestion")),
            replacing(wire(), at: ["params", "_meta", "tool_params", "app"], with: .string("  ")),
        ]
        let found = try CodexDesktopPermissions.pending(state(unrelated + [wire()]), threadID: threadID,
            ownerClientID: "desktop-owner", now: now)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.wireRequest, wire())
        XCTAssertThrowsError(try CodexDesktopPermissions.pending(.object([:]), threadID: threadID,
            ownerClientID: "desktop-owner", now: now))
    }

    func testIdentityNamespacingAndRPCIDTypesPreserveIntegerPrecision() throws {
        let numeric = try pending(wire(id: .integer(Int64.max)))
        let string = try pending(wire(id: .string(String(Int64.max))))
        XCTAssertEqual(numeric.requestID, .integer(Int64.max))
        XCTAssertNotEqual(numeric.id, string.id)
        let other = try XCTUnwrap(CodexDesktopPermissions.pending(
            state([wire(id: .integer(Int64.max), threadID: "other-thread")]), threadID: "other-thread",
            ownerClientID: "desktop-owner", now: now).first)
        XCTAssertNotEqual(numeric.id, other.id)
        XCTAssertEqual(numeric.id, try pending(wire(id: .integer(Int64.max))).id)
        let newOwner = try XCTUnwrap(CodexDesktopPermissions.pending(state([wire(id: .integer(Int64.max))]),
            threadID: threadID, ownerClientID: "replacement-owner", now: now).first)
        XCTAssertNotEqual(numeric.id, newOwner.id)
        let changedTerms = try pending(replacing(wire(id: .integer(Int64.max)),
            at: ["params", "_meta", "tool_params", "app"], with: .string("other.app")))
        XCTAssertEqual(numeric.requestID, changedTerms.requestID)
        XCTAssertNotEqual(numeric.id, changedTerms.id, "Changed native terms must replace the displayed card and its answer closure")
    }

    func testHighRiskNativeWarningIsPreservedWithTheBundleID() throws {
        let risky = replacing(replacing(wire(), at: ["params", "_meta", "riskLevel"], with: .string("high")),
            at: ["params", "_meta", "subtitle"], with: .string("This app can access sensitive information."))
        let item = try pending(risky)
        XCTAssertTrue(item.request.detail?.contains("This app can access sensitive information.") == true)
        XCTAssertTrue(item.request.detail?.contains("com.agenthud.app") == true)
        XCTAssertNotEqual(item.request.detail, "com.agenthud.app")
    }

    func testResponsesMatchNativeConversationAlwaysAndDenyChoices() throws {
        let item = try pending()
        XCTAssertEqual(try CodexDesktopPermissions.response(.allow, for: item), .object([
            "action": .string("accept"), "content": .object([:]), "_meta": .object(["persist": .string("session")]),
        ]))
        XCTAssertEqual(try CodexDesktopPermissions.response(.allowAlways(.object(["persist": .string("always")])), for: item), .object([
            "action": .string("accept"), "content": .object([:]), "_meta": .object(["persist": .string("always")]),
        ]))
        XCTAssertEqual(try CodexDesktopPermissions.response(.deny, for: item), .object([
            "action": .string("decline"), "content": .null, "_meta": .null,
        ]))
        XCTAssertNil(try CodexDesktopPermissions.response(.leave, for: item))
        XCTAssertThrowsError(try CodexDesktopPermissions.response(.answer([:]), for: item))
        XCTAssertThrowsError(try CodexDesktopPermissions.response(.allowAlways(.object([
            "persist": .string("always"), "extra": .bool(true),
        ])), for: item))
    }

    func testSessionOnlyRequestDoesNotOfferOrAcceptAlwaysAllow() throws {
        let item = try pending(wire(persist: .array([.string("session")])))
        XCTAssertNil(item.request.alwaysAllow)
        XCTAssertEqual(item.request.nativeApproval, .computerUseApp(persist: ["session"]))
        XCTAssertThrowsError(try CodexDesktopPermissions.response(.allowAlways(.object(["persist": .string("always")])), for: item))
    }

    func testFetchAndResolveUseOwnerSnapshotAndPreserveRawIntegerID() async throws {
        let raw = wire(id: .integer(Int64.max))
        let server = try CodexPermissionsTestServer(state: state([raw]))
        defer { server.stop() }
        let client = CodexDesktopPermissions(dataDirectory: server.directory, timeout: 1)
        let snapshot = try await client.fetch(threadIDs: [threadID])
        XCTAssertEqual(snapshot.observedThreadIDs, [threadID])
        let item = try XCTUnwrap(snapshot.pending.first)
        try await client.resolve(.allow, for: item)
        let answer = try XCTUnwrap(server.answers.first)
        XCTAssertEqual(answer["targetClientId"].stringValue, "desktop-owner")
        XCTAssertEqual(answer["version"], .integer(1))
        XCTAssertEqual(answer["params"]["requestId"], .integer(Int64.max))
        XCTAssertEqual(answer["params"]["response"]["_meta"]["persist"].stringValue, "session")
        XCTAssertEqual(server.methods.filter { $0 == "thread-owner-discovery" }.count, 2)
        XCTAssertEqual(server.methods.filter { $0 == "thread-stream-following-changed" }.count, 4)
    }

    func testChangedRequestOrOwnerNeverReceivesAnAnswer() async throws {
        let server = try CodexPermissionsTestServer(state: state([wire()]))
        defer { server.stop() }
        let client = CodexDesktopPermissions(dataDirectory: server.directory, timeout: 1)
        let snapshot = try await client.fetch(threadIDs: [threadID])
        let item = try XCTUnwrap(snapshot.pending.first)
        server.state = state([replacing(wire(), at: ["params", "_meta", "tool_params", "app"], with: .string("other.app"))])
        do { try await client.resolve(.allow, for: item); XCTFail("Changed permission cannot be approved") }
        catch let error as CodexDesktopPermissions.Failure { XCTAssertEqual(error, .noLongerWaiting) }
        server.state = state([wire()])
        server.owner = "new-owner"
        do { try await client.resolve(.deny, for: item); XCTFail("A new owner cannot answer the original permission") }
        catch let error as CodexDesktopPermissions.Failure { XCTAssertEqual(error, .noLongerWaiting) }
        XCTAssertTrue(server.answers.isEmpty)
    }

    func testAlwaysAndDenyDeliverTheNativeResponsesAndRequireOwnerAcknowledgement() async throws {
        for decision in [PermissionDecision.allowAlways(.object(["persist": .string("always")])), .deny] {
            let server = try CodexPermissionsTestServer(state: state([wire()]))
            defer { server.stop() }
            let client = CodexDesktopPermissions(dataDirectory: server.directory, timeout: 1)
            let item = try pending()
            try await client.resolve(decision, for: item)
            let answer = try XCTUnwrap(server.answers.first)
            XCTAssertEqual(answer["params"]["response"], try CodexDesktopPermissions.response(decision, for: item))
        }
        let server = try CodexPermissionsTestServer(state: state([wire()]), acknowledges: false)
        defer { server.stop() }
        do {
            try await CodexDesktopPermissions(dataDirectory: server.directory, timeout: 1).resolve(.allow, for: pending())
            XCTFail("A false owner receipt does not establish acceptance")
        } catch let error as CodexDesktopIPC.Failure { XCTAssertEqual(error, .acceptanceUncertain) }
        XCTAssertEqual(server.answers.count, 1, "An uncertain answer must never be automatically retried")
    }

    func testNoOwnerOrMalformedSnapshotIsUnknownAndLeaveDoesNotConnect() async throws {
        let server = try CodexPermissionsTestServer(state: .object([:]))
        defer { server.stop() }
        let client = CodexDesktopPermissions(dataDirectory: server.directory, timeout: 1)
        let malformed = try await client.fetch(threadIDs: [threadID])
        XCTAssertTrue(malformed.pending.isEmpty)
        XCTAssertTrue(malformed.observedThreadIDs.isEmpty)
        server.owner = nil
        let absent = try await client.fetch(threadIDs: [threadID])
        XCTAssertTrue(absent.observedThreadIDs.isEmpty)
        let before = server.methods
        try await client.resolve(.leave, for: pending())
        XCTAssertEqual(server.methods, before)
    }

    func testUnavailableSocketThrowsAndCancelledPreflightNeverAnswers() async throws {
        let missing = URL(fileURLWithPath: "/private/tmp/agenthud-missing-\(UUID().uuidString)")
        do {
            _ = try await CodexDesktopPermissions(dataDirectory: missing).fetch(threadIDs: [threadID])
            XCTFail("A missing native service is not an empty snapshot")
        } catch let error as CodexDesktopIPC.Failure { XCTAssertEqual(error, .unavailable) }
        let server = try CodexPermissionsTestServer(state: state([wire()]))
        defer { server.stop() }
        let client = CodexDesktopPermissions(dataDirectory: server.directory, timeout: 1)
        let item = try pending()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await client.resolve(.allow, for: item)
        }
        do { try await task.value; XCTFail("Cancelled preflight must stop") }
        catch is CancellationError { }
        XCTAssertTrue(server.answers.isEmpty)
    }
}

/// A private fixture hub. It answers only fixture-owned requests and never connects to Desktop's live socket.
private final class CodexPermissionsTestServer: @unchecked Sendable {
    let directory = URL(fileURLWithPath: "/private/tmp/agenthud-permission-\(UUID().uuidString.prefix(8))")
    private let listener: Int32
    private let lock = NSLock()
    private let finished = DispatchSemaphore(value: 0)
    private var stopped = false
    private var peer: Int32?
    private var fixtureState: JSONValue
    private var fixtureOwner: String? = "desktop-owner"
    private let acknowledges: Bool
    private var received: [JSONValue] = []
    var state: JSONValue {
        get { lock.withLock { fixtureState } }
        set { lock.withLock { fixtureState = newValue } }
    }
    var owner: String? {
        get { lock.withLock { fixtureOwner } }
        set { lock.withLock { fixtureOwner = newValue } }
    }
    var methods: [String] { lock.withLock { received.compactMap { $0["method"].stringValue } } }
    var answers: [JSONValue] {
        lock.withLock { received.filter { $0["method"].stringValue == "thread-follower-submit-mcp-server-elicitation-response" } }
    }

    init(state: JSONValue, acknowledges: Bool = true) throws {
        fixtureState = state
        self.acknowledges = acknowledges
        let folder = directory.appendingPathComponent("ipc")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent("ipc.sock").path
        listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0, UnixSocket.fits(path) else { throw FixtureFailure.socket }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { field in
            field.withMemoryRebound(to: CChar.self, capacity: 104) { strlcpy($0, path, 104) }
        }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, Darwin.listen(listener, 8) == 0 else {
            Darwin.close(listener)
            try? FileManager.default.removeItem(at: directory)
            throw FixtureFailure.socket
        }
        DispatchQueue.global().async { self.serve(); self.finished.signal() }
    }

    func stop() {
        let active = lock.withLock { () -> Int32? in stopped = true; return peer }
        if let active { Darwin.shutdown(active, SHUT_RDWR) }
        Darwin.close(listener)
        _ = finished.wait(timeout: .now() + 2)
        try? FileManager.default.removeItem(at: directory)
    }

    private func serve() {
        while !lock.withLock({ stopped }) {
            var entry = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            guard poll(&entry, 1, 100) > 0, entry.revents & Int16(POLLIN) != 0 else { continue }
            let connection = Darwin.accept(listener, nil, nil)
            guard connection >= 0 else { return }
            lock.withLock { peer = connection }
            var receiveTimeout = timeval(tv_sec: 1, tv_usec: 0), on: Int32 = 1
            setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            do { while true { try handle(receive(connection), peer: connection) } } catch { }
            Darwin.close(connection)
            lock.withLock { peer = nil }
        }
    }

    private func handle(_ message: JSONValue, peer: Int32) throws {
        lock.withLock { received.append(message) }
        let method = message["method"].stringValue ?? ""
        if method == "thread-stream-following-changed" {
            if message["params"]["following"].boolValue == true, let owner {
                try send(peer, .object([
                    "type": .string("broadcast"), "method": .string("thread-stream-state-changed"), "version": .integer(11),
                    "sourceClientId": .string(owner), "params": .object([
                        "hostId": .string("local"), "conversationId": message["params"]["conversationId"],
                        "change": .object(["type": .string("snapshot"), "revision": .integer(1), "conversationState": state]),
                    ]),
                ]))
            }
            return
        }
        var reply: [String: JSONValue] = ["type": .string("response"), "requestId": message["requestId"], "resultType": .string("success")]
        switch method {
        case "initialize": reply["result"] = .object(["clientId": .string("fixture-client")])
        case "thread-owner-discovery":
            if let owner {
                reply["handledByClientId"] = .string(owner)
                reply["result"] = .object([:])
            } else {
                reply["resultType"] = .string("error")
                reply["error"] = .string("no-client-found")
            }
        case "thread-follower-submit-mcp-server-elicitation-response":
            reply["handledByClientId"] = owner.map(JSONValue.string) ?? .null
            reply["result"] = .object(["method": .string(method), "result": .object(["ok": .bool(acknowledges)])])
        default: throw FixtureFailure.protocolError
        }
        try send(peer, .object(reply))
    }

    private func send(_ peer: Int32, _ message: JSONValue) throws {
        let payload = try RecordCoding.encoder().encode(message)
        var length = UInt32(payload.count).littleEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(payload)
        guard UnixSocket.send(peer, frame) else { throw FixtureFailure.socket }
    }

    private func receive(_ peer: Int32) throws -> JSONValue {
        let header = try read(peer, count: 4)
        let length = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        guard length > 0, length <= 1024 * 1024 else { throw FixtureFailure.protocolError }
        return try JSONValue.parse(read(peer, count: Int(length)))
    }

    private func read(_ peer: Int32, count: Int) throws -> Data {
        var result = Data()
        while result.count < count {
            var bytes = [UInt8](repeating: 0, count: min(count - result.count, 4096))
            let size = Darwin.recv(peer, &bytes, bytes.count, 0)
            if size < 0, errno == EINTR { continue }
            guard size > 0 else { throw FixtureFailure.socket }
            result.append(contentsOf: bytes.prefix(size))
        }
        return result
    }

    private enum FixtureFailure: Error { case socket, protocolError }
}
