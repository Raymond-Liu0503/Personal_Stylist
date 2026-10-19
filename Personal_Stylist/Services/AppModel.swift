import Foundation
import Observation

@MainActor @Observable final class AppModel {
    enum Flow: String { case home, camera, review, processing, result }
    enum Tab: Hashable { case home, saved, account }
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
    var tab: Tab = .home
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
    var analysisBlock: String? { bootstrap?.analysisBlock ?? (bootstrap == nil ? "Account access could not be checked. Refresh access to try again." : nil) }
    var validIntent: Bool { (try? intent.context(custom: customIntent)) != nil && prompt.utf16.count <= 1000 }
    func start() async {
        starting = true; error = nil; startupFailed = false
        do {
            try await photos.sweep()
            try auth.restore(); signedIn = auth.userID != nil
            if signedIn { await refresh() }
        } catch { self.error = error.localizedDescription; startupFailed = true }
        starting = false
    }
    func resetStartup() async {
        await perform {
            try await auth.signOut()
            await start()
        }
    }
    func refresh() async {
        guard signedIn else { return }
        let epoch = UUID(); refreshGeneration = epoch
        do {
            let value = try await api.bootstrap()
            guard refreshGeneration == epoch, signedIn else { return }
            bootstrap = value
        } catch is CancellationError { }
        catch {
            guard refreshGeneration == epoch, signedIn else { return }
            bootstrap = nil; self.error = error.localizedDescription
        }
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
            await refresh()
        }
    }
    func localSignIn(email: String, password: String) async {
        await perform {
            try await auth.signInLocal(email: email, password: password)
            signedIn = true
            try await api.consent(true)
            await refresh()
        }
    }
    func acceptConsent() async { await perform { try await api.consent(true); await refresh() } }
    func prepare(_ data: Data) async {
        guard !preparing && !submitting else { return }
        let epoch = UUID(); generation = epoch
        preparing = true; error = nil
        defer { if generation == epoch { preparing = false } }
        do {
            photo = nil
            // A previous cleanup failure must be resolved before accepting another photo.
            try await photos.sweep()
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
                let bytes = try Data(contentsOf: photo.url)
                let metadata = try AnalysisMetadata(prompt: capturedPrompt, context: capturedIntent.context(custom: capturedCustom))
                let response = try await api.analyze(image: bytes, metadata: metadata, requestID: requestID)
                guard generation == epoch, !Task.isCancelled else { return }
                result = response; self.photo = nil; flow = .result
                do { try await photos.remove(photo) } catch { self.error = "Temporary-photo cleanup failed. Close the assessment and retry cleanup before continuing." }
            } catch is CancellationError { }
            catch { if generation == epoch { self.error = error.localizedDescription } }
            if generation == epoch { submitting = false; analysisTask = nil }
            await refresh()
        }
    }
    func clearAnalysis(preserveBrief: Bool = false) async throws {
        generation = UUID()
        let task = analysisTask; analysisTask = nil; task?.cancel()
        submitting = false; preparing = false
        photo = nil; result = nil; savedID = nil; reportFeedbackSent = false; suggestionFeedback = [:]
        if !preserveBrief { prompt = ""; intent = .general; customIntent = "" }
        await task?.value
        try await photos.sweep()
    }
    func navigate(_ destination: Flow, preserveBrief: Bool = false) async {
        await perform { try await clearAnalysis(preserveBrief: preserveBrief); flow = destination; tab = .home }
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
            await refresh(); notice = "Preferences saved."
        }
    }
    func withdrawConsent() async {
        await perform {
            try await clearAnalysis(); clearHistory()
            try await api.consent(false); await refresh(); flow = .home; tab = .home
        }
    }
    private func localSignOut() async throws {
        signedIn = false; bootstrap = nil; refreshGeneration = UUID(); clearHistory(); timer = 0; flow = .home; tab = .home
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
