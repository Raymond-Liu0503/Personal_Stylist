import Foundation
import Security

protocol CredentialStorage {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func remove() throws
}
struct KeychainStorage: CredentialStorage {
    let account: String
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.personalstylist.native.auth", kSecAttrAccount as String: account] }
    func read() throws -> Data? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StylistError.message("Secure sign-in storage is unavailable. Unlock your iPhone and retry.") }
        return result as? Data
    }
    func write(_ data: Data) throws {
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw StylistError.message("Your sign-in could not be stored securely.") }; return
        }
        guard update == errSecSuccess else { throw StylistError.message("Your sign-in could not be stored securely.") }
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StylistError.message("Secure sign-out could not finish. Unlock your iPhone and retry.") }
    }
}

@MainActor final class AuthService: SessionProviding {
    private let config: AppConfiguration
    private let transport: any HTTPTransport
    private let storage: any CredentialStorage
    private var session: AuthSession?
    private var refreshTask: Task<AuthSession, Error>?
    private(set) var generation = UUID()
    var userID: String? { session?.user.id }
    init(config: AppConfiguration, transport: any HTTPTransport = URLSessionTransport(), storage: (any CredentialStorage)? = nil) {
        self.config = config; self.transport = transport
        self.storage = storage ?? KeychainStorage(account: config.supabaseURL.absoluteString)
    }
    func restore() throws {
        if let data = try storage.read() { session = try JSONDecoder().decode(AuthSession.self, from: data) }
    }
    private func exchange(grant: String, body: [String: String]) async throws -> AuthSession {
        guard config.configured else { throw StylistError.message("Add your public Supabase configuration to LocalConfig.plist before signing in.") }
        var components = URLComponents(url: config.supabaseURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: grant)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"; request.httpBody = try JSONEncoder().encode(body)
        request.setValue(config.publicKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw StylistError.api("UNAUTHENTICATED", "Sign-in could not be completed. Check your account and configuration, then try again.")
        }
        var session = try JSONDecoder().decode(AuthSession.self, from: data)
        guard UUID(uuidString: session.user.id) != nil, !session.access_token.isEmpty, !session.refresh_token.isEmpty else { throw StylistError.message("Invalid sign-in response.") }
        if session.expires_at == nil { session.expires_at = Date().timeIntervalSince1970 + (session.expires_in ?? 3600) }
        return session
    }
    private func install(_ newSession: AuthSession) throws {
        try storage.write(JSONEncoder().encode(newSession)); session = newSession
    }
    func signInApple(token: String, nonce: String) async throws {
        let epoch = generation
        let value = try await exchange(grant: "id_token", body: ["provider": "apple", "id_token": token, "nonce": nonce])
        guard epoch == generation else { throw CancellationError() }
        try install(value); generation = UUID()
    }
    func signInLocal(email: String, password: String) async throws {
        guard config.allowsLocalLogin else { throw StylistError.message("Local test sign-in is unavailable in this build.") }
        let epoch = generation
        let value = try await exchange(grant: "password", body: ["email": email, "password": password])
        guard epoch == generation else { throw CancellationError() }
        try install(value); generation = UUID()
    }
    func validSession() async throws -> AuthSession {
        guard let current = session else { throw StylistError.api("UNAUTHENTICATED", "Please sign in again.") }
        if (current.expires_at ?? 0) > Date().timeIntervalSince1970 + 60 { return current }
        if let refreshTask { return try await refreshTask.value }
        let epoch = generation
        let task = Task { try await self.exchange(grant: "refresh_token", body: ["refresh_token": current.refresh_token]) }
        refreshTask = task
        defer { if epoch == generation { refreshTask = nil } }
        let value = try await task.value
        guard generation == epoch, value.user.id == current.user.id else { throw CancellationError() }
        try install(value); return value
    }
    func signOut() async throws {
        let old = session
        generation = UUID(); refreshTask?.cancel(); refreshTask = nil; session = nil
        try storage.remove()
        if let old {
            var request = URLRequest(url: config.supabaseURL.appendingPathComponent("auth/v1/logout"))
            request.url = URL(string: request.url!.absoluteString + "?scope=local")
            request.httpMethod = "POST"
            request.setValue("Bearer \(old.access_token)", forHTTPHeaderField: "Authorization")
            request.setValue(config.publicKey, forHTTPHeaderField: "apikey")
            _ = try? await transport.send(request)
        }
    }
}

