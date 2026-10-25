import Foundation
import UIKit

extension AppModel {
    static func makeDefault() -> AppModel {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let transport = FixtureTransport()
            return AppModel(config: AppConfiguration(supabaseURL: URL(string: "http://127.0.0.1:54321")!, publicKey: "ui-tests-only", apiVersion: "v1", environment: "local"), transport: transport, storage: MemoryCredentialStorage())
        }
        #endif
        return AppModel()
    }
    #if DEBUG
    func prepareTestPhoto() async {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400)).image { context in
            UIColor.brown.setFill(); context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
        }
        await prepare(image.jpegData(compressionQuality: 0.8)!)
    }
    #endif
}

#if DEBUG
final class MemoryCredentialStorage: CredentialStorage {
    var data: Data?
    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
    func remove() throws { data = nil }
}

actor FixtureTransport: HTTPTransport {
    static let userID = "11111111-1111-4111-8111-111111111111"
    static let runID = "22222222-2222-4222-8222-222222222222"
    static let savedID = "33333333-3333-4333-8333-333333333333"
    static let reportJSON = """
    {"schemaVersion":1,"runId":"22222222-2222-4222-8222-222222222222","status":"complete","summary":"A balanced outfit with a clear, relaxed direction.","overallScore":8.5,"verdict":"works_well","criteria":[{"id":"silhouette","applicable":true,"score":4,"observation":"The proportions are balanced.","explanation":"The layers have a clear shape."},{"id":"colour","applicable":true,"score":4,"observation":"The colours work together.","explanation":"The palette has a quiet contrast."},{"id":"coherence","applicable":true,"score":4,"observation":"The pieces share a relaxed feel.","explanation":"The styling reads consistently."},{"id":"finishing","applicable":true,"score":5,"observation":"The visible details look considered.","explanation":"The shoes complete the outfit."},{"id":"intent","applicable":false,"score":null,"observation":"No occasion was specified.","explanation":"This assessment focuses on the visible outfit."}],"strengths":["Balanced proportions","A cohesive palette"],"suggestions":[{"observation":"The sleeves cover the wrist.","action":"Try a small sleeve cuff.","reason":"It gives the layers a clearer finish.","kind":"restyle"}],"limitations":[],"versions":{"agent":"outfit","skill":"fixture","rubric":"v1","model":"mock"}}
    """
    private var accepted = false
    private var saved = false
    private var preferences: JSONValue = .object([:])
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let path = request.url!.path
        let method = request.httpMethod ?? "GET"
        var status = 200
        let report = try JSONDecoder().decode(JSONValue.self, from: Data(Self.reportJSON.utf8))
        let row: JSONValue = .object(["id": .string(Self.savedID), "created_at": .string("2026-10-18T12:00:00Z"), "report": report])
        var payload: JSONValue = .object([:])
        if path.hasSuffix("/token") {
            payload = .object(["access_token": .string("test-access"), "refresh_token": .string("test-refresh"), "expires_at": .number(Date().timeIntervalSince1970 + 3600), "expires_in": .number(3600), "user": .object(["id": .string(Self.userID)])])
        } else if path.hasSuffix("/bootstrap") {
            payload = .object(["analysisMode": .string("mock"), "dailyQuotaExempt": .bool(false), "profile": preferences, "policyVersion": .string(Contracts.policyVersion), "consentAccepted": .bool(accepted), "features": .object(["outfit": .bool(true)]), "remainingQuota": .number(3), "betaAccess": .bool(true)])
        } else if path.hasSuffix("/consents") {
            let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody!)
            accepted = body["accepted"] == .bool(true); payload = .object(["accepted": .bool(accepted)])
        } else if path.hasSuffix("/profile") {
            preferences = try JSONDecoder().decode(JSONValue.self, from: request.httpBody!); payload = preferences
        } else if path.hasSuffix("/analyze/outfit") {
            if ProcessInfo.processInfo.arguments.contains("--slow-analysis") { try await Task.sleep(for: .seconds(10)) }
            if ProcessInfo.processInfo.arguments.contains("--retake") { payload = .object(["kind": .string("retake"), "issues": .array([.string("too_dark")]), "instructions": .array([.string("Find even light and try again.")])]) }
            else if ProcessInfo.processInfo.arguments.contains("--invalid-output") { payload = .object(["kind": .string("report"), "report": .string("invalid")]) }
            else if ProcessInfo.processInfo.arguments.contains("--partial"), case .object(var fields) = report {
                fields["status"] = .string("partial"); fields["overallScore"] = .null; fields["verdict"] = .null
                payload = .object(["kind": .string("report"), "report": .object(fields), "receipt": .string("fixture-receipt")])
            } else { payload = .object(["kind": .string("report"), "report": report, "receipt": .string("fixture-receipt")]) }
        } else if path.hasSuffix("/reports") && method == "POST" { saved = true; payload = row; status = 201 }
        else if path.hasSuffix("/reports") { payload = .object(["items": .array(saved ? [row] : []), "nextCursor": .null]) }
        else if path.contains("/reports/") && method == "DELETE" { saved = false; payload = .object(["deleted": .bool(true)]) }
        else if path.hasSuffix("/feedback") { payload = .object(["received": .bool(true)]) }
        else if path.hasSuffix("/logout") { status = 204 }
        else { status = 404; payload = .object(["error": .object(["code": .string("NOT_FOUND"), "message": .string("Missing test route.")])]) }
        return (try JSONEncoder().encode(payload), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
    }
}
#endif
