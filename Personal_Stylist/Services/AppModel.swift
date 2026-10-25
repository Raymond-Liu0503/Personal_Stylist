import Foundation
import Observation

@MainActor @Observable final class AppModel {
    enum Flow: String { case home, camera, review, processing, result }
    enum Sheet: String, Identifiable { case saved, account; var id: String { rawValue } }
    let config: AppConfiguration
    @ObservationIgnored let auth: AuthService
    @ObservationIgnored let api: APIClient
    @ObservationIgnored let photos: PhotoService
    @ObservationIgnored private let apple = AppleAuthorization()
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var refreshGeneration = UUID()
    var signedIn = false
    var starting = true
    var startupFailed = false
    var bootstrap: Bootstrap?
    var busy = false
    var error: String?
    var notice: String?
    var sheet: Sheet?
    var refreshing = false
    var accessError: String?
    var resultReadyAt: TimeInterval?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    var flow: Flow = .home
    var photo: PreparedPhoto?
    var preparing = false
    var submitting = false
    var result: AnalysisResult?
    var prompt = ""
    var intent: IntentPreset = .general
    var customIntent = ""
    var timer = 0
    var savedID: String?
    var reportFeedbackSent = false
    var suggestionFeedback: [Int: Bool] = [:]
    var history: [SavedReport] = []
    var historyCursor: String?
    var historyLoading = false
    var historyNavigationID = UUID()
    @ObservationIgnored private var historyGeneration = UUID()

    init(config: AppConfiguration = .load(), transport: any HTTPTransport = URLSessionTransport(), storage: (any CredentialStorage)? = nil, photos: PhotoService = PhotoService()) {
        self.config = config; self.photos = photos
        auth = AuthService(config: config, transport: transport, storage: storage)
        api = APIClient(configuration: config, auth: auth, transport: transport)
    }
    var onboarded: Bool { signedIn && bootstrap?.hasConsent == true }
    var analysisBlock: String? { refreshing ? "Checking access…" : bootstrap?.analysisBlock ?? (bootstrap == nil ? (accessError ?? "Account access could not be checked. Refresh access to try again.") : nil) }
    var validIntent: Bool { (try? intent.context(custom: customIntent)) != nil && prompt.utf16.count <= 1000 }
    func start() async {
        let started = PerformanceTrace.now
        starting = true; error = nil; startupFailed = false
        invalidateRefresh(); bootstrap = nil
        do {
            try await photos.sweep()
            try auth.restore(); signedIn = auth.userID != nil
        } catch { self.error = error.localizedDescription; startupFailed = true }
        starting = false
        PerformanceTrace.finish("local_startup", since: started)
        if signedIn && !startupFailed { await refresh() }
    }
    func resetStartup() async {
        await perform {
            invalidateRefresh(); signedIn = false; bootstrap = nil
            try await auth.signOut()
            await start()
        }
    }
    private func invalidateRefresh() {
        refreshGeneration = UUID()
        refreshTask?.cancel(); refreshTask = nil; refreshing = false
    }
    func refresh(force: Bool = false) async {
        guard signedIn, !starting else { return }
        if force { invalidateRefresh() }
        if let refreshTask { await refreshTask.value; return }
        let epoch = UUID(); refreshGeneration = epoch
        refreshing = true
        let task = Task { @MainActor in
            let started = PerformanceTrace.now
            defer {
                PerformanceTrace.finish("account_refresh", since: started)
                if refreshGeneration == epoch { refreshTask = nil; refreshing = false }
            }
            do {
                let value = try await api.bootstrap()
                guard refreshGeneration == epoch, signedIn, !Task.isCancelled else { return }
                bootstrap = value; accessError = nil
            } catch is CancellationError { }
            catch {
                guard refreshGeneration == epoch, signedIn else { return }
                bootstrap = nil; accessError = error.localizedDescription
            }
        }
        refreshTask = task
        await task.value
    }
    func perform(_ operation: () async throws -> Void) async {
        guard !busy else { return }
        busy = true; error = nil; notice = nil
        defer { busy = false }
        do { try await operation() }
        catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
    func appleSignIn() async {
        await perform {
            let credential = try await apple.authorize()
            try await auth.signInApple(token: credential.token, nonce: credential.nonce)
            signedIn = true
            try await api.consent(true)
            await refresh(force: true)
        }
    }
    func localSignIn(email: String, password: String) async {
        await perform {
            try await auth.signInLocal(email: email, password: password)
            signedIn = true
            try await api.consent(true)
            await refresh(force: true)
        }
    }
    func acceptConsent() async { await perform { invalidateRefresh(); try await api.consent(true); await refresh(force: true) } }
    func prepare(_ data: Data) async {
        guard onboarded, !preparing, !submitting else { return }
        let epoch = UUID(); generation = epoch
        let started = PerformanceTrace.now
        preparing = true; error = nil
        defer { PerformanceTrace.finish("photo_preparation", since: started); if generation == epoch { preparing = false } }
        do {
            photo = nil
            // A previous cleanup failure must be resolved before accepting another photo.
            try await photos.sweep()
            guard generation == epoch, signedIn, !Task.isCancelled else { return }
            let value = try await photos.prepare(data)
            guard generation == epoch, signedIn, !Task.isCancelled else { try await photos.remove(value); return }
            photo = value; flow = .review
        } catch is CancellationError { }
        catch { if generation == epoch { self.error = error.localizedDescription } }
    }
    func submit() {
        guard analysisTask == nil, !submitting, !preparing, let photo, analysisBlock == nil, validIntent else { return }
        let epoch = UUID(); generation = epoch
        let requestID = UUID().uuidString.lowercased()
        let capturedPrompt = prompt, capturedIntent = intent, capturedCustom = customIntent
        submitting = true; error = nil; flow = .processing
        analysisTask = Task {
            do {
                let bytes = try await photos.read(photo)
                try Task.checkCancellation()
                let metadata = try AnalysisMetadata(prompt: capturedPrompt, context: capturedIntent.context(custom: capturedCustom))
                let response = try await api.analyze(image: bytes, metadata: metadata, requestID: requestID)
                guard generation == epoch, !Task.isCancelled else { return }
                result = response; resultReadyAt = PerformanceTrace.now; self.photo = nil; flow = .result
                do { try await photos.remove(photo) } catch { if generation == epoch { self.error = "Temporary-photo cleanup failed. Close the assessment and retry cleanup before continuing." } }
            } catch is CancellationError { }
            catch { if generation == epoch { self.error = error.localizedDescription } }
            if generation == epoch {
                submitting = false; analysisTask = nil
                Task {
                    guard generation == epoch, signedIn else { return }
                    await refresh(force: true)
                }
            }
        }
    }
    func clearAnalysis(preserveBrief: Bool = false) async throws {
        generation = UUID()
        let task = analysisTask; analysisTask = nil; task?.cancel()
        submitting = false; preparing = false
        photo = nil; result = nil; resultReadyAt = nil; savedID = nil; reportFeedbackSent = false; suggestionFeedback = [:]
        if !preserveBrief { prompt = ""; intent = .general; customIntent = "" }
        try await photos.sweep()
        if task != nil, signedIn {
            let session = auth.generation
            Task {
                guard signedIn, auth.generation == session else { return }
                await refresh(force: true)
            }
        }
    }
    func navigate(_ destination: Flow, preserveBrief: Bool = false) async {
        await perform { try await clearAnalysis(preserveBrief: preserveBrief); flow = destination; sheet = nil }
    }
    func saveReport() async {
        guard let result, savedID == nil else { return }
        await perform {
            let row = try await api.save(result)
            savedID = row.id; notice = "Your text report is saved."
        }
    }
    func sendFeedback(helpful: Bool, suggestion: Int? = nil) async {
        guard let report = result?.report else { return }
        await perform {
            var body: [String: JSONValue] = ["helpful": .bool(helpful)]
            if let suggestion {
                guard (0..<min(3, report.suggestions.count)).contains(suggestion), suggestionFeedback[suggestion] == nil else { return }
                body["runId"] = .string(report.runId); body["suggestionIndex"] = .number(Double(suggestion))
            } else {
                guard !reportFeedbackSent else { return }
                body["issues"] = .array(helpful ? [] : [.string("invented_details")])
                if let savedID { body["savedReportId"] = .string(savedID) }
            }
            try await api.confirm("/feedback", body: JSONEncoder().encode(JSONValue.object(body)), key: "received")
            if let suggestion { suggestionFeedback[suggestion] = helpful } else { reportFeedbackSent = true }
        }
    }
    func loadHistory(older: Bool = false) async {
        guard !historyLoading else { return }
        let epoch = UUID(); historyGeneration = epoch; historyLoading = true; error = nil
        defer { if historyGeneration == epoch { historyLoading = false } }
        do {
            let page = try await api.history(cursor: older ? historyCursor : nil)
            guard historyGeneration == epoch else { return }
            history = older ? history + page.items.filter { item in !history.contains(where: { $0.id == item.id }) } : page.items
            historyCursor = page.nextCursor
        } catch is CancellationError { }
        catch { if historyGeneration == epoch { self.error = error.localizedDescription } }
    }
    func clearHistory() { historyGeneration = UUID(); historyNavigationID = UUID(); history = []; historyCursor = nil; historyLoading = false }
    func deleteReport(_ id: String) async {
        await perform {
            try await api.confirm("/reports/\(id)", method: "DELETE", body: nil, key: "deleted")
            history.removeAll { $0.id == id }
        }
    }
    func savePreferences(style: String, constraints: String) async {
        await perform {
            let style = style.trimmingCharacters(in: .whitespacesAndNewlines)
            let lines = constraints.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let preferences = try Preferences(desiredStyle: style.isEmpty ? nil : style, constraints: lines.isEmpty ? nil : lines).validated()
            _ = try Contracts.decode(Preferences.self, data: await api.request("/profile", method: "PUT", body: JSONEncoder().encode(preferences)), schema: Contracts.preferences)
            await refresh(force: true); notice = "Preferences saved."
        }
    }
    func withdrawConsent() async {
        await perform {
            try await clearAnalysis(); clearHistory()
            invalidateRefresh(); bootstrap = nil
            try await api.consent(false); await refresh(force: true); flow = .home; sheet = nil
        }
    }
    private func localSignOut() async throws {
        invalidateRefresh(); signedIn = false; bootstrap = nil; clearHistory(); timer = 0; flow = .home; sheet = nil
        // Always attempt both credential removal and photo cleanup, even if either fails.
        var failure: Error?
        do { try await clearAnalysis() } catch { failure = error }
        do { try await auth.signOut() } catch { failure = error }
        if let failure { throw failure }
    }
    func signOut() async { await perform { try await localSignOut() } }
    func deleteAccount() async {
        await perform {
            try await clearAnalysis()
            // Keep the original Supabase identity. The backend verifies this fresh Apple code
            // against that identity; re-signing in here could switch the account being deleted.
            let credential = try await apple.authorize()
            try await api.confirm("/account", method: "DELETE", body: JSONEncoder().encode(["authorizationCode": credential.code]), key: "deleted")
            try await localSignOut()
        }
    }
}
