import Foundation

protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class URLSessionTransport: NSObject, HTTPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    override init() { super.init(); _ = session }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw StylistError.message("The service returned an unreadable response.") }
            return (data, http)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            if error.code == .timedOut { throw StylistError.api("TIMEOUT", "The request reached its deadline. An already-started analysis may count toward your allowance.") }
            throw StylistError.api("NETWORK", "The connection ended. An already-started analysis may count toward your allowance.")
        }
    }
    // Never forward photos or bearer tokens through redirects.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct AuthSession: Codable, Sendable {
    struct User: Codable, Sendable { let id: String }
    let access_token: String
    let refresh_token: String
    var expires_at: Double?
    let expires_in: Double?
    let user: User
}

@MainActor protocol SessionProviding: AnyObject {
    var userID: String? { get }
    var generation: UUID { get }
    func validSession() async throws -> AuthSession
}

@MainActor final class APIClient {
    let configuration: AppConfiguration
    let auth: any SessionProviding
    let transport: any HTTPTransport
    init(configuration: AppConfiguration, auth: any SessionProviding, transport: any HTTPTransport = URLSessionTransport()) {
        self.configuration = configuration; self.auth = auth; self.transport = transport
    }
    func request(_ path: String, method: String = "GET", body: Data? = nil, contentType: String = "application/json", requestID: String? = nil, query: [URLQueryItem] = []) async throws -> Data {
        let started = PerformanceTrace.now
        defer { if path == "/analyze/outfit" { PerformanceTrace.finish("analysis_request", since: started, id: requestID ?? "none") } }
        let generation = auth.generation
        let session = try await auth.validSession()
        try Task.checkCancellation()
        guard generation == auth.generation else { throw CancellationError() }
        var components = URLComponents(url: configuration.supabaseURL.appendingPathComponent("functions/v1/api/\(configuration.apiVersion)\(path)"), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 60
        request.setValue("Bearer \(session.access_token)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.publicKey, forHTTPHeaderField: "apikey")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if let requestID { request.setValue(requestID, forHTTPHeaderField: "Idempotency-Key") }
        let (data, response) = try await transport.send(request)
        try Task.checkCancellation()
        guard generation == auth.generation, session.user.id == auth.userID else { throw CancellationError() }
        guard (200..<300).contains(response.statusCode) else {
            struct Failure: Decodable { struct Detail: Decodable { let code: String; let message: String }; let error: Detail }
            if let error = try? JSONDecoder().decode(Failure.self, from: data), error.error.message.utf16.count <= 500 {
                throw StylistError.api(error.error.code, error.error.message)
            }
            throw StylistError.message("The request could not be completed (\(response.statusCode)).")
        }
        return data
    }
    func bootstrap() async throws -> Bootstrap { try Contracts.decode(Bootstrap.self, data: await request("/bootstrap"), schema: Contracts.bootstrap) }
    func confirm(_ path: String, method: String = "POST", body: Data?, key: String) async throws {
        let data = try await request(path, method: method, body: body)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        try WireSchema.object([key: .bool]).validate(value)
        if key != "accepted", value[key] != .bool(true) { throw StylistError.message("The operation did not finish. Please retry.") }
    }
    func consent(_ accepted: Bool) async throws {
        let data = try JSONEncoder().encode(JSONValue.object(["policyVersion": .string(Contracts.policyVersion), "accepted": .bool(accepted), "adultConfirmed": .bool(accepted)]))
        let response = try await request("/consents", method: "POST", body: data)
        let raw = try JSONDecoder().decode(JSONValue.self, from: response)
        try WireSchema.object(["accepted": .bool]).validate(raw)
        guard raw["accepted"] == .bool(accepted) else { throw StylistError.message("Consent could not be updated.") }
    }
    func analyze(image: Data, metadata: AnalysisMetadata, requestID: String) async throws -> AnalysisResult {
        let boundary = "Stylist-\(UUID().uuidString)"
        let body = try Multipart.encode(image: image, metadata: metadata, boundary: boundary)
        return try AnalysisResult.decode(await request("/analyze/outfit", method: "POST", body: body, contentType: "multipart/form-data; boundary=\(boundary)", requestID: requestID))
    }
    func save(_ result: AnalysisResult) async throws -> SavedReport {
        let data = try await request("/reports", method: "POST", body: result.saveBody())
        let saved = try Contracts.decode(SavedReport.self, data: data, schema: Contracts.saved)
        try saved.report.validate(); return saved
    }
    func history(cursor: String? = nil) async throws -> HistoryPage {
        let data = try await request("/reports", query: cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [])
        let page = try Contracts.decode(HistoryPage.self, data: data, schema: Contracts.history)
        try page.items.forEach { try $0.report.validate() }; return page
    }
}
