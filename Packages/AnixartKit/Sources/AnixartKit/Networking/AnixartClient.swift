import Foundation

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
        await tokenStore.token() != nil
    }

    // MARK: - Sending

    @discardableResult
    public func send<Response: Decodable & Sendable>(_ endpoint: Endpoint<Response>) async throws -> Response {
        let request = try await urlRequest(for: endpoint)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AnixartError.wrapping(transportError: error)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AnixartError.http(statusCode: http.statusCode, path: endpoint.path)
        }

        let decoded: Response
        do {
            decoded = try decoder.decode(Response.self, from: data)
        } catch {
            throw AnixartError.decoding(message: String(describing: error), path: endpoint.path)
        }

        // Anixart reports business failures in the body, not the HTTP status.
        if let envelope = decoded as? any AnixartResponse,
           let code = envelope.code,
           code != AnixartStatus.successful {
            throw AnixartError.api(code: code, path: endpoint.path)
        }

        return decoded
    }

    // MARK: - Request building

    /// Builds the `URLRequest` an endpoint would send.
    ///
    /// Public so callers can log a request, and so the token/query/body rules can be
    /// asserted in tests without going near the network.
    public func urlRequest<Response: Decodable & Sendable>(
        for endpoint: Endpoint<Response>
    ) async throws -> URLRequest {
        let token = await tokenStore.token()
        if case .required = endpoint.auth, token == nil {
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
        case .optional, .required:
            if let token {
                items.append(URLQueryItem(name: "token", value: token))
            }
        }
        components.queryItems = items.isEmpty ? nil : items

        guard let url = components.url else {
            throw AnixartError.invalidURL(path: endpoint.path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue(configuration.apiVersion, forHTTPHeaderField: "API-Version")
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
        }

        return request
    }
}
