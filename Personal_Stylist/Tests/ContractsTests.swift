import XCTest
#if SWIFT_PACKAGE
@testable import StylistCore
#else
@testable import PersonalStylist
#endif

final class ContractsTests: XCTestCase {
    static func report(score: JSONValue = .number(8.5)) -> JSONValue {
        .object([
            "schemaVersion": .number(1), "runId": .string("ABCDEFAB-1234-4234-8234-ABCDEFABCDEF"), "status": .string("partial"),
            "summary": .string("A considered outfit."), "overallScore": score, "verdict": .null,
            "criteria": .array(Contracts.criterionIDs.sorted().map { .object(["id": .string($0), "applicable": .bool($0 != "intent"), "score": .null, "observation": .string("Visible detail."), "explanation": .string("A clear explanation.")]) }),
            "strengths": .array([]), "suggestions": .array([.object(["observation": .string("A loose cuff."), "action": .string("Roll the cuff."), "reason": .string("Reveal the wrist.")])]),
            "limitations": .array([]), "versions": .object(["agent": .string("outfit"), "skill": .string("v1"), "rubric": .string("v1"), "model": .string("mock")])
        ])
    }
    static func envelope(_ report: JSONValue) throws -> Data {
        try JSONEncoder().encode(JSONValue.object(["kind": .string("report"), "report": report, "receipt": .string("signed-receipt")]))
    }
    func testReceiptSavePreservesNullableFieldsUUIDCaseAndAbsentSuggestionKind() throws {
        let report = Self.report()
        let response = try AnalysisResult.decode(Self.envelope(report))
        let saved = try JSONDecoder().decode(JSONValue.self, from: response.saveBody())
        XCTAssertEqual(saved["report"], report)
        XCTAssertEqual(saved["receipt"], .string("signed-receipt"))
        XCTAssertEqual(response.report?.runId, "ABCDEFAB-1234-4234-8234-ABCDEFABCDEF")
    }
    func testInvalidScoreAndMarkupAreRejected() throws {
        XCTAssertThrowsError(try AnalysisResult.decode(Self.envelope(Self.report(score: .number(8.3)))))
        guard case .object(var report) = Self.report() else { return XCTFail() }
        report["summary"] = .string("<script>invalid</script>")
        XCTAssertThrowsError(try AnalysisResult.decode(Self.envelope(.object(report))))
    }
    func testDuplicateCriteriaAndUnknownFieldsAreRejected() throws {
        guard case .object(var report) = Self.report(), case .array(var criteria) = report["criteria"] else { return XCTFail() }
        criteria[1] = criteria[0]; report["criteria"] = .array(criteria)
        XCTAssertThrowsError(try AnalysisResult.decode(Self.envelope(.object(report))))
        guard case .object(var report) = Self.report() else { return XCTFail() }
        report["extra"] = .string("unexpected")
        XCTAssertThrowsError(try AnalysisResult.decode(Self.envelope(.object(report))))
    }
    func testRetakeAndPartialUnratedReport() throws {
        let data = Data(#"{"kind":"retake","issues":["too_dark"],"instructions":["Find even light."]}"#.utf8)
        let retake = try AnalysisResult.decode(data)
        XCTAssertNil(retake.report); XCTAssertEqual(retake.instructions, ["Find even light."])
        XCTAssertThrowsError(try retake.saveBody())
        let partial = try AnalysisResult.decode(Self.envelope(Self.report(score: .null)))
        XCTAssertEqual(partial.report?.status, "partial"); XCTAssertNil(partial.report?.overallScore)
    }
    func testIntentDoesNotInventOccasionAndCustomIsValidated() throws {
        XCTAssertEqual(try IntentPreset.general.context(custom: "ignored"), [:])
        XCTAssertEqual(try IntentPreset.morePolished.context(custom: ""), ["desiredStyle": "A more polished presentation"])
        XCTAssertEqual(try IntentPreset.custom.context(custom: "  relaxed  "), ["desiredStyle": "relaxed"])
        XCTAssertThrowsError(try IntentPreset.custom.context(custom: "https://example.com"))
        XCTAssertThrowsError(try IntentPreset.custom.context(custom: " "))
        XCTAssertThrowsError(try IntentPreset.custom.context(custom: String(repeating: "x", count: 161)))
    }
    func testLocalLoginIsRestrictedToPrivateHTTPBackend() {
        for host in ["127.0.0.1", "localhost", "10.2.3.4", "172.16.0.1", "192.168.1.8"] {
            XCTAssertTrue(AppConfiguration.isLocal(environment: "local", url: URL(string: "http://\(host):54321")!))
        }
        for url in ["https://localhost:54321", "http://localhost:80", "http://192.168.999.1:54321", "http://172.32.0.1:54321", "http://example.com:54321", "http://localhost.evil.test:54321"] {
            XCTAssertFalse(AppConfiguration.isLocal(environment: "local", url: URL(string: url)!))
        }
        XCTAssertFalse(AppConfiguration.isLocal(environment: "beta", url: URL(string: "http://localhost:54321")!))
    }
    func testMultipartUsesExactFieldNamesAndImageBytes() throws {
        let jpeg = Data([0xff, 0xd8, 0xff, 0x00, 0xff, 0xd9])
        let body = try Multipart.encode(image: jpeg, metadata: AnalysisMetadata(prompt: "Question", context: [:]), boundary: "test-boundary")
        XCTAssertNotNil(body.range(of: Data("name=\"metadata\"".utf8)))
        XCTAssertNotNil(body.range(of: Data("name=\"image\"; filename=\"outfit.jpg\"".utf8)))
        XCTAssertNotNil(body.range(of: jpeg))
        XCTAssertTrue(body.suffix(21).contains(0x0a))
        XCTAssertThrowsError(try Multipart.encode(image: Data(), metadata: AnalysisMetadata(prompt: "", context: [:]), boundary: "x"))
        XCTAssertThrowsError(try Multipart.encode(image: jpeg, metadata: AnalysisMetadata(prompt: String(repeating: "x", count: 1001), context: [:]), boundary: "x"))
    }
    func testPreferencesAndBootstrapBounds() throws {
        XCTAssertThrowsError(try Preferences(desiredStyle: nil, constraints: Array(repeating: "x", count: 11)).validated())
        let data = Data(#"{"profile":{},"policyVersion":"2026-09-01","consentAccepted":true,"features":{"outfit":true},"remainingQuota":4,"betaAccess":true}"#.utf8)
        XCTAssertThrowsError(try Contracts.decode(Bootstrap.self, data: data, schema: Contracts.bootstrap))
    }
}

private struct TestTransport: HTTPTransport {
    let operation: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { try await operation(request) }
}
@MainActor private final class TestSession: SessionProviding {
    var generation = UUID()
    var userID: String? = "11111111-1111-4111-8111-111111111111"
    func validSession() async throws -> AuthSession { AuthSession(access_token: "access", refresh_token: "refresh", expires_at: Date().timeIntervalSince1970 + 3600, expires_in: 3600, user: .init(id: userID!)) }
}
final class APITests: XCTestCase {
    @MainActor func testSessionChangeDiscardsInFlightResponse() async throws {
        let auth = TestSession()
        let transport = TestTransport { request in
            await MainActor.run { auth.generation = UUID() }
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let api = APIClient(configuration: .init(supabaseURL: URL(string: "https://example.com")!, publicKey: "public", apiVersion: "v1", environment: "beta"), auth: auth, transport: transport)
        do { _ = try await api.request("/bootstrap"); XCTFail("Stale response accepted") } catch is CancellationError { } catch { XCTFail("Wrong error: \(error)") }
    }
    @MainActor func testAPIPathAuthenticationAndIdempotency() async throws {
        let auth = TestSession()
        let transport = TestTransport { request in
            XCTAssertEqual(request.url?.path, "/functions/v1/api/v1/analyze/outfit")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "request-id")
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let api = APIClient(configuration: .init(supabaseURL: URL(string: "https://example.com")!, publicKey: "public", apiVersion: "v1", environment: "beta"), auth: auth, transport: transport)
        _ = try await api.request("/analyze/outfit", method: "POST", requestID: "request-id")
    }
    @MainActor func testServerFailureIsNotRetried() async throws {
        actor Counter { var count = 0; func increment() { count += 1 } }
        let counter = Counter()
        let transport = TestTransport { request in
            await counter.increment()
            return (Data(#"{"error":{"code":"QUOTA_EXHAUSTED","message":"Daily allowance used."}}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!)
        }
        let api = APIClient(configuration: .init(supabaseURL: URL(string: "https://example.com")!, publicKey: "public", apiVersion: "v1", environment: "beta"), auth: TestSession(), transport: transport)
        do { _ = try await api.request("/analyze/outfit", method: "POST"); XCTFail() }
        catch let error as StylistError { XCTAssertEqual(error, .api("QUOTA_EXHAUSTED", "Daily allowance used.")) }
        let count = await counter.count; XCTAssertEqual(count, 1)
    }
}

private final class TestCredentialStorage: CredentialStorage {
    var data: Data?
    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
    func remove() throws { data = nil }
}
final class AuthTests: XCTestCase {
    @MainActor func testConcurrentRefreshUsesOneRequestAndStoresRotatedToken() async throws {
        let storage = TestCredentialStorage()
        let old = AuthSession(access_token: "old", refresh_token: "old-refresh", expires_at: 1, expires_in: 1, user: .init(id: "11111111-1111-4111-8111-111111111111"))
        try storage.write(JSONEncoder().encode(old))
        actor Counter { var count = 0; func increment() { count += 1 } }
        let counter = Counter()
        let transport = TestTransport { request in
            await counter.increment()
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "refresh_token")
            try await Task.sleep(for: .milliseconds(20))
            let value = AuthSession(access_token: "new", refresh_token: "rotated", expires_at: Date().timeIntervalSince1970 + 3600, expires_in: 3600, user: old.user)
            return (try JSONEncoder().encode(value), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let auth = AuthService(config: .init(supabaseURL: URL(string: "https://example.com")!, publicKey: "public", apiVersion: "v1", environment: "beta"), transport: transport, storage: storage)
        try auth.restore()
        async let first = auth.validSession()
        async let second = auth.validSession()
        let sessions = try await [first, second]
        XCTAssertEqual(sessions.map(\.access_token), ["new", "new"])
        XCTAssertEqual(try JSONDecoder().decode(AuthSession.self, from: storage.read()!).refresh_token, "rotated")
        let count = await counter.count; XCTAssertEqual(count, 1)
    }
    @MainActor func testSignOutInvalidatesPendingRefreshAndClearsStorage() async throws {
        let storage = TestCredentialStorage()
        let old = AuthSession(access_token: "old", refresh_token: "refresh", expires_at: 1, expires_in: 1, user: .init(id: "11111111-1111-4111-8111-111111111111"))
        try storage.write(JSONEncoder().encode(old))
        let transport = TestTransport { request in
            if request.url!.path.hasSuffix("/token") { try await Task.sleep(for: .seconds(1)) }
            return (try JSONEncoder().encode(old), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let auth = AuthService(config: .init(supabaseURL: URL(string: "https://example.com")!, publicKey: "public", apiVersion: "v1", environment: "beta"), transport: transport, storage: storage)
        try auth.restore()
        let refresh = Task { try await auth.validSession() }
        await Task.yield()
        try await auth.signOut()
        _ = try? await refresh.value
        XCTAssertNil(auth.userID); XCTAssertNil(try storage.read())
    }
}
