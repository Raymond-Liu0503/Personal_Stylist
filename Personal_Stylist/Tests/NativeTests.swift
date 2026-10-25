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

// Deliberately holds completed responses even when the caller cancels, exercising
// generation guards against transports that deliver late callbacks.
private actor HeldResponseTransport: HTTPTransport {
    let base = FixtureTransport()
    private var failurePath: String?
    func fail(_ path: String?) { failurePath = path }
    private var heldPath: String?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var pending: Int { waiters.count }
    func hold(_ path: String) { heldPath = path }
    func release() {
        heldPath = nil
        let pending = waiters; waiters = []
        pending.forEach { $0.resume() }
    }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let failurePath, request.url!.path.hasSuffix(failurePath) { throw StylistError.message("Offline") }
        let response = try await base.send(request)
        if let heldPath, request.url!.path.hasSuffix(heldPath) {
            await withCheckedContinuation { waiters.append($0) }
        }
        return response
    }
}

@MainActor final class CameraFirstFlowTests: XCTestCase {
    private func model(_ transport: HeldResponseTransport) -> AppModel {
        AppModel(config: .init(supabaseURL: URL(string: "http://127.0.0.1:54321")!, publicKey: "test", apiVersion: "v1", environment: "local"), transport: transport, storage: MemoryCredentialStorage(), photos: PhotoService(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
    }
    private func waitForPending(_ transport: HeldResponseTransport, count: Int = 1) async throws {
        for _ in 0..<200 {
            if await transport.pending >= count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Request did not reach the response gate")
    }
    private func signIn(_ model: AppModel) async {
        await model.start()
        await model.localSignIn(email: "test@example.com", password: "test")
    }
    func testStartupShowsShellBeforeAccountRequestCompletes() async throws {
        let transport = HeldResponseTransport(), model = model(transport)
        await signIn(model)
        await transport.hold("/bootstrap")
        let startup = Task { await model.start() }
        try await waitForPending(transport)
        XCTAssertFalse(model.starting)
        XCTAssertTrue(model.signedIn)
        XCTAssertTrue(model.refreshing)
        XCTAssertFalse(model.onboarded)
        XCTAssertNotNil(model.analysisBlock)
        await transport.release(); await startup.value
        XCTAssertTrue(model.onboarded)
    }
    func testConcurrentAccountRefreshesShareRequest() async throws {
        let transport = HeldResponseTransport(), model = model(transport)
        await signIn(model)
        let before = await transport.base.requests.count
        await transport.hold("/bootstrap")
        let first = Task { await model.refresh() }
        try await waitForPending(transport)
        let second = Task { await model.refresh() }
        try await Task.sleep(for: .milliseconds(20))
        let during = await transport.base.requests.count
        XCTAssertEqual(during - before, 1)
        await transport.release(); await first.value; await second.value
        XCTAssertFalse(model.refreshing)
    }
    func testForcedRefreshCannotReuseOldConsentResponse() async throws {
        let transport = HeldResponseTransport(), model = model(transport)
        await signIn(model)
        await transport.hold("/bootstrap")
        let old = Task { await model.refresh() }
        try await waitForPending(transport)
        let withdrawal = Task { await model.withdrawConsent() }
        try await waitForPending(transport, count: 2)
        await transport.release(); await old.value; await withdrawal.value
        XCTAssertFalse(model.onboarded)
        XCTAssertFalse(model.refreshing)
    }
    func testSignOutDiscardsHeldAccountResponse() async throws {
        let transport = HeldResponseTransport(), model = model(transport)
        await signIn(model)
        await transport.hold("/bootstrap")
        let refresh = Task { await model.refresh() }
        try await waitForPending(transport)
        await model.signOut()
        await transport.release(); await refresh.value
        XCTAssertFalse(model.signedIn)
        XCTAssertNil(model.bootstrap)
        XCTAssertFalse(model.refreshing)
    }
    func testCancellationDoesNotWaitForAnalysisOrAcceptLateResult() async throws {
        let transport = HeldResponseTransport(), model = model(transport)
        await signIn(model)
        await model.prepareTestPhoto()
        let photoURL = try XCTUnwrap(model.photo?.url)
        await transport.hold("/analyze/outfit")
        model.submit()
        try await waitForPending(transport)
        let began = PerformanceTrace.now
        await model.navigate(.home, preserveBrief: true)
        XCTAssertLessThan(PerformanceTrace.now - began, 1)
        XCTAssertEqual(model.flow, .home)
        XCTAssertFalse(model.submitting)
        XCTAssertFalse(FileManager.default.fileExists(atPath: photoURL.path))
        await transport.release()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(model.result)
        XCTAssertEqual(model.flow, .home)
        await model.prepareTestPhoto()
        XCTAssertEqual(model.flow, .review)
        try await model.clearAnalysis()
    }
    func testAccountFailureBlocksCaptureAndRetryRecovers() async throws {
        let transport = HeldResponseTransport(), model = model(transport)
        await signIn(model)
        await transport.fail("/bootstrap")
        await model.refresh()
        XCTAssertFalse(model.onboarded)
        XCTAssertEqual(model.accessError, "Offline")
        await model.prepareTestPhoto()
        XCTAssertNil(model.photo)
        await transport.fail(nil)
        await model.refresh()
        XCTAssertTrue(model.onboarded)
        XCTAssertNil(model.accessError)
        XCTAssertNil(model.analysisBlock)
    }
    func testCancelCountdownKeepsPreviewReadyAndCannotCancelNewCountdown() async throws {
        let camera = CameraModel()
        camera.ready = true
        camera.takePhoto(timer: 10) { _ in XCTFail("Canceled countdown captured a photo") }
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(camera.countdown, 10)
        camera.cancelCountdown()
        XCTAssertTrue(camera.ready)
        XCTAssertFalse(camera.busy)
        camera.takePhoto(timer: 3) { _ in XCTFail("Canceled countdown captured a photo") }
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertTrue(camera.busy)
        XCTAssertEqual(camera.countdown, 3)
        camera.cancelCountdown()
        XCTAssertTrue(camera.ready)
        XCTAssertNil(camera.countdown)
    }

}
