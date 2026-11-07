import Foundation
import XCTest
import AnixartKit
@testable import Anixart

func profileTestDecode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
    try JSONDecoder().decode(type, from: Data(json.utf8))
}

/// Each rig has its own .invalid host and response queue. Parallel tests cannot
/// steal one another's requests, and no request can reach a real account.
@MainActor
final class ProfileTestRig {
    let api: ProfileTestAPI
    let client: AnixartClient
    let session: SessionController

    init(store: any TokenStore = InMemoryTokenStore()) {
        let api = ProfileTestAPI()
        self.api = api
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileTestURLProtocol.self]
        client = AnixartClient(configuration: .init(baseURL: api.baseURL), tokenStore: store, sessionConfiguration: configuration)
        session = SessionController(client: client, tokenStore: store)
    }

    deinit { api.close() }

    func signIn(profileID: Int = 42, token: String = "test-token") async throws {
        api.enqueue("/auth/signIn", json: ProfileTestAPI.signInJSON(profileID: profileID, token: token))
        try await session.signIn(login: "test-user", password: "test-password")
    }
}

final class ProfileTestAPI: @unchecked Sendable {
    fileprivate enum Plan {
        case response(String, Int)
        case held(ProfileHeldRequest)
    }

    let baseURL: URL
    private let lock = NSLock()
    private var plans: [String: [Plan]] = [:]
    private var received: [URLRequest] = []

    init() {
        baseURL = URL(string: "https://\(UUID().uuidString.lowercased()).profile-tests.invalid/")!
        ProfileTestURLProtocol.register(self)
    }

    func close() { ProfileTestURLProtocol.unregister(self) }

    static func signInJSON(profileID: Int, token: String) -> String {
        "{\"code\":0,\"profile\":{\"id\":\(profileID)},\"profileToken\":{\"id\":1,\"token\":\"\(token)\"}}"
    }

    func enqueue(_ path: String, json: String, status: Int = 200) {
        lock.lock()
        defer { lock.unlock() }
        plans[path, default: []].append(.response(json, status))
    }

    func hold(_ path: String) -> ProfileHeldRequest {
        let held = ProfileHeldRequest(path: path)
        lock.lock()
        plans[path, default: []].append(.held(held))
        lock.unlock()
        return held
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return received
    }

    func requests(to path: String) -> [URLRequest] { requests.filter { $0.url?.path == path } }

    fileprivate func next(for request: URLRequest) -> Plan {
        let path = request.url?.path ?? ""
        lock.lock()
        received.append(request)
        if var queue = plans[path], !queue.isEmpty {
            let next = queue.removeFirst()
            plans[path] = queue
            lock.unlock()
            return next
        }
        lock.unlock()
        // Session refreshes are deliberately boring. All feature endpoints
        // must be scripted explicitly, including intentional failures.
        if path == "/notification/count" { return .response(#"{"code":0,"count":0}"#, 200) }
        // Обзор's collections-of-the-week block is decorative and loaded with every
        // refresh; tests that care about it enqueue it explicitly above.
        if path == "/collection/all/0" { return .response(#"{"code":0,"content":[]}"#, 200) }
        let parts = path.split(separator: "/")
        if parts.count == 2, parts[0] == "profile", let id = Int(parts[1]) {
            return .response("{\"code\":0,\"profile\":{\"id\":\(id)}}", 200)
        }
        XCTFail("Unscripted test API request: \(path)")
        return .response(#"{"code":999999}"#, 500)
    }
}

/// Requests remain in flight until a test releases them. A response may also
/// be provided before arrival, so a failed expectation never leaves a hang.
final class ProfileHeldRequest: @unchecked Sendable {
    let arrived: XCTestExpectation
    let cancelled: XCTestExpectation
    private let lock = NSLock()
    private var received: URLRequest?
    private var reply: (String, Int)?
    private var delivery: (@Sendable (String, Int) -> Void)?
    private var isCancelled = false

    init(path: String) {
        arrived = XCTestExpectation(description: "Received \(path)")
        cancelled = XCTestExpectation(description: "Cancelled \(path)")
    }

    var request: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return received
    }

    func respond(_ json: String, status: Int = 200) {
        lock.lock()
        guard !isCancelled, reply == nil else { lock.unlock(); return }
        reply = (json, status)
        let complete = delivery
        delivery = nil
        lock.unlock()
        complete?(json, status)
    }

    fileprivate func bind(_ request: URLRequest, delivery: @escaping @Sendable (String, Int) -> Void) {
        lock.lock()
        received = request
        let reply = self.reply
        let isCancelled = self.isCancelled
        if reply == nil, !isCancelled { self.delivery = delivery }
        lock.unlock()
        arrived.fulfill()
        if !isCancelled, let (json, status) = reply { delivery(json, status) }
    }

    fileprivate func cancel() {
        lock.lock()
        guard !isCancelled, reply == nil else { lock.unlock(); return }
        isCancelled = true
        delivery = nil
        lock.unlock()
        cancelled.fulfill()
    }
}

private final class ProfileTestURLProtocol: URLProtocol, @unchecked Sendable {
    private static let registryLock = NSLock()
    private static var registry: [String: ProfileTestAPI] = [:]
    private let lock = NSLock()
    private var waiting: ProfileHeldRequest?
    private var hasEnded = false

    static func register(_ api: ProfileTestAPI) {
        registryLock.lock()
        defer { registryLock.unlock() }
        registry[api.baseURL.host!] = api
    }

    static func unregister(_ api: ProfileTestAPI) {
        registryLock.lock()
        defer { registryLock.unlock() }
        registry[api.baseURL.host!] = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.registryLock.lock()
        let api = (request.url?.host).flatMap { Self.registry[$0] }
        Self.registryLock.unlock()
        guard let api else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        let request = Self.materialized(request)
        switch api.next(for: request) {
        case .response(let json, let status): complete(json, status: status)
        case .held(let held):
            lock.lock()
            guard !hasEnded else { lock.unlock(); held.cancel(); return }
            waiting = held
            lock.unlock()
            held.bind(request) { [weak self] json, status in self?.complete(json, status: status) }
        }
    }

    override func stopLoading() {
        lock.lock()
        hasEnded = true
        let waiting = self.waiting
        self.waiting = nil
        lock.unlock()
        waiting?.cancel()
    }

    private func complete(_ json: String, status: Int) {
        lock.lock()
        guard !hasEnded else { lock.unlock(); return }
        hasEnded = true
        waiting = nil
        lock.unlock()
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])
        else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func materialized(_ request: URLRequest) -> URLRequest {
        guard request.httpBody == nil, let stream = request.httpBodyStream else { return request }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: 4096)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        var copy = request
        copy.httpBodyStream = nil
        copy.httpBody = data
        return copy
    }
}

/// Unlike Task.sleep, this gate does not react to cancellation. It can model
/// an async token store that has already written when a login gets cancelled.
final class ProfileTestGate: @unchecked Sendable {
    let entered = XCTestExpectation(description: "Entered suspended operation")
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var hasEntered = false
    private var isReleased = false

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            let shouldNotify = !hasEntered
            hasEntered = true
            let released = isReleased
            if !released { continuations.append(continuation) }
            lock.unlock()
            if shouldNotify { entered.fulfill() }
            if released { continuation.resume() }
        }
    }

    func release() {
        lock.lock()
        isReleased = true
        let continuations = self.continuations
        self.continuations = []
        lock.unlock()
        for continuation in continuations { continuation.resume() }
    }
}

actor ProfileControlledTokenStore: TokenStore {
    enum Kind: Hashable, Sendable { case save, replace, clear }
    enum Write: Equatable, Sendable {
        case save(String, Int)
        case replace(String, Int, String)
        case clear
    }

    private var storedToken: String?
    private var storedID: Int?
    private var gates: [Kind: [ProfileTestGate]] = [:]
    private(set) var writes: [Write] = []
    private(set) var tokenReads = 0

    init(token: String? = nil, profileID: Int? = nil) { storedToken = token; storedID = profileID }
    func token() -> String? { tokenReads += 1; return storedToken }
    func profileID() -> Int? { storedID }

    func pauseNext(_ kind: Kind) -> ProfileTestGate {
        let gate = ProfileTestGate()
        gates[kind, default: []].append(gate)
        return gate
    }

    func save(token: String, profileID: Int) async throws {
        writes.append(.save(token, profileID))
        storedToken = token
        storedID = profileID
        if let gate = nextGate(.save) { await gate.wait() }
    }

    func replace(token: String, profileID: Int, expectedToken: String) async throws -> Bool {
        writes.append(.replace(token, profileID, expectedToken))
        guard storedToken == expectedToken, storedID == profileID else { return false }
        storedToken = token
        if let gate = nextGate(.replace) { await gate.wait() }
        return true
    }

    func clear() async throws {
        writes.append(.clear)
        storedToken = nil
        storedID = nil
        if let gate = nextGate(.clear) { await gate.wait() }
    }

    private func nextGate(_ kind: Kind) -> ProfileTestGate? {
        guard var queue = gates[kind], !queue.isEmpty else { return nil }
        let gate = queue.removeFirst()
        gates[kind] = queue
        return gate
    }
}
