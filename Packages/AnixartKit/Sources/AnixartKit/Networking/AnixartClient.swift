import Foundation
import os

/// Talks to the Anixart backend.
///
/// Three behaviours are inherited from the Android client rather than invented here:
///
/// 1. The session token is a `token` query parameter, not a header.
/// 2. Failure arrives as HTTP 200 with a non-zero `code` in the body, so every
///    response is checked after decoding (see `AnixartResponse`).
/// 3. The base host is not fixed: `config/urls` returns the live list and the app
///    is expected to switch to it, optionally through `mirror-`prefixed hosts when
///    the server sets `shouldUseMirrorUrls`.
public actor AnixartClient {
    public struct Configuration: Sendable {
        public var baseURL: URL
        public var apiVersion: String
        public var timeout: TimeInterval
        /// Rewrite image and API hosts to their `mirror-` form, as `config/urls` requests.
        public var useMirrorHosts: Bool

        public init(
            baseURL: URL = AnixartEnvironment.defaultBaseURL,
            apiVersion: String = AnixartEnvironment.apiVersion,
            timeout: TimeInterval = 30,
            useMirrorHosts: Bool = false
        ) {
            self.baseURL = baseURL
            self.apiVersion = apiVersion
            self.timeout = timeout
            self.useMirrorHosts = useMirrorHosts
        }
    }

    /// Failed calls are logged rather than swallowed: the app surfaces a message to
    /// the user, but the path and status that caused it are only useful in a log.
    private static let log = Logger(subsystem: "app.anixart.client", category: "api")

    private var configuration: Configuration
    private let tokenStore: any TokenStore
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(
        configuration: Configuration = Configuration(),
        tokenStore: any TokenStore,
        sessionConfiguration: URLSessionConfiguration = .default
    ) {
        self.configuration = configuration
        self.tokenStore = tokenStore

        sessionConfiguration.timeoutIntervalForRequest = configuration.timeout
        sessionConfiguration.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: sessionConfiguration)

        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    public var currentConfiguration: Configuration { configuration }

    /// Adopts the hosts the server advertises through `config/urls`.
    public func apply(_ urls: ConfigUrlsResponse) {
        // An expired launch operation can reach this actor after its caller's
        // pre-hop check. Do not let it replace the host of requests already begun.
        guard !Task.isCancelled else { return }
        if let first = urls.apiUrls?.first {
            let normalized = first.hasSuffix("/") ? first : first + "/"
            if let url = URL(string: normalized) {
                configuration.baseURL = url
            }
        }
        if let mirror = urls.shouldUseMirrorUrls {
            configuration.useMirrorHosts = mirror
        }
    }

    public func update(baseURL: URL) {
        configuration.baseURL = baseURL
    }

    public func isAuthenticated() async -> Bool {
        await tokenStore.token()?.isEmpty == false
    }

    // MARK: - Sending

    @discardableResult
    public func send<Response: Decodable & Sendable>(_ endpoint: Endpoint<Response>) async throws -> Response {
        try Task.checkCancellation()
        let request = try await urlRequest(for: endpoint)
        try Task.checkCancellation()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            Self.log.error("transport failure for \(endpoint.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw AnixartError.wrapping(transportError: error)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            Self.log.error("HTTP \(http.statusCode, privacy: .public) for \(endpoint.path, privacy: .public)")
            throw AnixartError.http(statusCode: http.statusCode, path: endpoint.path)
        }

        // Bare-array endpoints still use a {"code": ...} envelope on failure.
        // Check it first so a business error isn't disguised as a shape mismatch.
        if let status = try? decoder.decode(CodeEnvelope.self, from: data),
           let code = status.code, !endpoint.acceptedStatusCodes.contains(code) {
            Self.log.error("API code \(code, privacy: .public) for \(endpoint.path, privacy: .public)")
            throw AnixartError.api(code: code, path: endpoint.path)
        }

        let decoded: Response
        do {
            decoded = try decoder.decode(Response.self, from: data)
        } catch {
            // The single most likely failure in this port: a JSON key that does not
            // match what the server actually sends. Worth the log line.
            Self.log.error("decode failed for \(endpoint.path, privacy: .public): \(String(describing: error), privacy: .public)")
            throw AnixartError.decoding(message: String(describing: error), path: endpoint.path)
        }

        // Anixart reports business failures in the body, not the HTTP status.
        if let envelope = decoded as? any AnixartResponse,
           let code = envelope.code,
           !endpoint.acceptedStatusCodes.contains(code) {
            Self.log.error("API code \(code, privacy: .public) for \(endpoint.path, privacy: .public)")
            throw AnixartError.api(code: code, path: endpoint.path)
        }

        return decoded
    }

    private struct CodeEnvelope: Decodable { let code: Int? }

    // MARK: - Request building

    /// Builds the `URLRequest` an endpoint would send.
    ///
    /// Public so callers can log a request, and so the token/query/body rules can be
    /// asserted in tests without going near the network.
    public func urlRequest<Response: Decodable & Sendable>(
        for endpoint: Endpoint<Response>
    ) async throws -> URLRequest {
        try Task.checkCancellation()
        let token: String?
        switch endpoint.auth {
        case .none: token = nil
        case .optional, .required, .matchingToken: token = await tokenStore.token()
        }
        try Task.checkCancellation()
        if case .required = endpoint.auth, token?.isEmpty != false {
            throw AnixartError.notAuthenticated(path: endpoint.path)
        }
        if case .matchingToken(let expected) = endpoint.auth, expected.isEmpty || token != expected {
            throw AnixartError.notAuthenticated(path: endpoint.path)
        }

        var base = configuration.baseURL
        if configuration.useMirrorHosts {
            base = AnixartURL.mirrored(base)
        }

        guard var components = URLComponents(
            url: base.appendingPathComponent(endpoint.path),
            resolvingAgainstBaseURL: false
        ) else {
            throw AnixartError.invalidURL(path: endpoint.path)
        }

        var items: [URLQueryItem] = endpoint.query
            .compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
            .sorted { $0.name < $1.name }

        switch endpoint.auth {
        case .none:
            break
        case .optional, .required, .matchingToken:
            if let token, !token.isEmpty {
                items.append(URLQueryItem(name: "token", value: token))
            }
        }
        components.queryItems = items.isEmpty ? nil : items

        guard let url = components.url else {
            throw AnixartError.invalidURL(path: endpoint.path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        // Two switches for finding out why the server refuses writes (comments, votes)
        // from this client; both are off unless the viewer turns them on in
        // Настройки → Диагностика → Совместимость запросов.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "diagnostics.omitAPIVersion") {
            request.setValue(configuration.apiVersion, forHTTPHeaderField: "API-Version")
        }
        if defaults.bool(forKey: "diagnostics.androidUserAgent") {
            // What the Android app's HTTP library announces itself as.
            request.setValue("okhttp/5.1.0", forHTTPHeaderField: "User-Agent")
        }
        for (field, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        switch endpoint.body {
        case nil:
            break
        case .json(let payload):
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try encoder.encode(payload)
            } catch {
                throw AnixartError.decoding(message: String(describing: error), path: endpoint.path)
            }
        case .form(let fields):
            request.setValue(
                "application/x-www-form-urlencoded; charset=utf-8",
                forHTTPHeaderField: "Content-Type"
            )
            request.httpBody = AnixartURL.formEncoded(fields).data(using: .utf8)
        case .multipart(let body):
            request.setValue("multipart/form-data; boundary=\(body.boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = body.encoded()
        }

        return request
    }
}
