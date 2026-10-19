import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

private final class SmokeCredentials: CredentialStorage {
    var data: Data?
    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
    func remove() throws { data = nil }
}

@main struct LocalSmoke {
    @MainActor static func main() async {
        do { try await run() }
        catch { FileHandle.standardError.write(Data("Local smoke check: \(error.localizedDescription)\n".utf8)); exit(1) }
    }
    @MainActor private static func run() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let key = env["STYLIST_PUBLIC_KEY"], let email = env["STYLIST_TEST_EMAIL"], let password = env["STYLIST_TEST_PASSWORD"], let url = URL(string: env["STYLIST_URL"] ?? "http://127.0.0.1:54321") else {
            throw StylistError.message("Set STYLIST_PUBLIC_KEY, STYLIST_TEST_EMAIL and STYLIST_TEST_PASSWORD for a disposable local test account.")
        }
        guard AppConfiguration.isLocal(environment: "local", url: url) else { throw StylistError.message("This smoke check only runs against the local backend.") }
        let config = AppConfiguration(supabaseURL: url, publicKey: key, apiVersion: "v1", environment: "local")
        let auth = AuthService(config: config, storage: SmokeCredentials())
        let api = APIClient(configuration: config, auth: auth)
        try await auth.signInLocal(email: email, password: password)
        do {
            let initial = try await api.bootstrap()
            guard initial.analysisMode == "mock" else { throw StylistError.message("Refusing to run: backend must use mock inference.") }
            try await api.consent(true)
            let bootstrap = try await api.bootstrap()
            guard bootstrap.analysisBlock == nil else { throw StylistError.message(bootstrap.analysisBlock!) }
            let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.setFillColor(CGColor(gray: 0.5, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            let bytes = NSMutableData()
            let destination = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, context.makeImage()!, nil)
            guard CGImageDestinationFinalize(destination) else { throw StylistError.message("Could not generate test JPEG.") }
            let result = try await api.analyze(image: bytes as Data, metadata: .init(prompt: "", context: [:]), requestID: UUID().uuidString.lowercased())
            guard result.report != nil else { throw StylistError.message("Use the default mock scenario for this smoke check.") }
            let saved = try await api.save(result)
            do {
                let repeated = try await api.save(result)
                guard repeated.id == saved.id else { throw StylistError.message("Save was not idempotent.") }
                let history = try await api.history()
                guard history.items.contains(where: { $0.id == saved.id }) else { throw StylistError.message("Saved report is missing from history.") }
                let feedback = JSONValue.object(["savedReportId": .string(saved.id), "helpful": .bool(true), "issues": .array([])])
                try await api.confirm("/feedback", body: JSONEncoder().encode(feedback), key: "received")
                try await api.confirm("/reports/\(saved.id)", method: "DELETE", body: nil, key: "deleted")
            } catch {
                try? await api.confirm("/reports/\(saved.id)", method: "DELETE", body: nil, key: "deleted")
                throw error
            }
            try await auth.signOut()
            print("PASS: local auth, consent, multipart analysis, signed/idempotent save, history, feedback, and report deletion.")
        } catch {
            try? await auth.signOut()
            throw error
        }
    }
}
