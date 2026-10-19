import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import PersonalStylist

final class AppFlowTests: XCTestCase {
    @MainActor func testCompleteMockFlowAndRepeatedSubmit() async throws {
        let transport = FixtureTransport()
        let model = AppModel(config: .init(supabaseURL: URL(string: "http://127.0.0.1:54321")!, publicKey: "test", apiVersion: "v1", environment: "local"), transport: transport, storage: MemoryCredentialStorage(), photos: PhotoService(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        await model.start(); await model.localSignIn(email: "test@example.com", password: "test")
        XCTAssertTrue(model.onboarded)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60)).image { context in UIColor.brown.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 60)) }
        await model.prepare(image.jpegData(compressionQuality: 0.8)!)
        XCTAssertEqual(model.flow, .review)
        model.intent = .work; model.submit(); model.submit()
        for _ in 0..<200 { if !model.submitting { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.flow, .result)
        XCTAssertNil(model.photo)
        let requests = await transport.requests
        XCTAssertEqual(requests.filter { $0.url!.path.hasSuffix("/analyze/outfit") }.count, 1)
        await model.saveReport(); XCTAssertNotNil(model.savedID)
        await model.loadHistory(); XCTAssertEqual(model.history.count, 1)
        await model.sendFeedback(helpful: true, suggestion: 0); XCTAssertEqual(model.suggestionFeedback[0], true)
        await model.deleteReport(model.history[0].id); XCTAssertTrue(model.history.isEmpty)
        try await model.clearAnalysis(preserveBrief: true); XCTAssertEqual(model.intent, .work); XCTAssertNil(model.result)
        try await model.clearAnalysis(); XCTAssertEqual(model.intent, .general)
        await model.withdrawConsent(); XCTAssertFalse(model.onboarded)
        await model.signOut(); XCTAssertFalse(model.signedIn)
    }
    @MainActor func testExpiredSessionRefreshIsStored() async throws {
        let storage = MemoryCredentialStorage()
        let expired = AuthSession(access_token: "old", refresh_token: "refresh", expires_at: 1, expires_in: 1, user: .init(id: FixtureTransport.userID))
        try storage.write(JSONEncoder().encode(expired))
        let auth = AuthService(config: .init(supabaseURL: URL(string: "http://127.0.0.1:54321")!, publicKey: "test", apiVersion: "v1", environment: "local"), transport: FixtureTransport(), storage: storage)
        try auth.restore()
        let session = try await auth.validSession()
        XCTAssertEqual(session.access_token, "test-access")
        XCTAssertEqual(try JSONDecoder().decode(AuthSession.self, from: storage.read()!).access_token, "test-access")
        try await auth.signOut(); XCTAssertNil(try storage.read())
    }
}
