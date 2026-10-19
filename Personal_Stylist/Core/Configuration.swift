import Foundation

struct AppConfiguration: Sendable {
    var supabaseURL: URL
    var publicKey: String
    var apiVersion: String
    var environment: String
    var configured: Bool { !publicKey.isEmpty && !publicKey.contains("REPLACE") && supabaseURL.host != nil && apiVersion == "v1" && (supabaseURL.scheme == "https" || allowsLocalLogin) }
    var allowsLocalLogin: Bool {
        #if DEBUG
        return Self.isLocal(environment: environment, url: supabaseURL)
        #else
        return false
        #endif
    }
    static func isLocal(environment: String, url: URL) -> Bool {
        guard environment == "local", url.scheme == "http", url.port == 54321, let host = url.host else { return false }
        if host == "localhost" || host == "127.0.0.1" { return true }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        return octets[0] == 10 || (octets[0] == 192 && octets[1] == 168) || (octets[0] == 172 && (16...31).contains(octets[1]))
    }
    static func load(bundle: Bundle = .main) -> AppConfiguration {
        let url = bundle.url(forResource: "LocalConfig", withExtension: "plist")
        let dict = url.flatMap { NSDictionary(contentsOf: $0) } as? [String: String] ?? [:]
        return AppConfiguration(supabaseURL: URL(string: dict["SUPABASE_URL"] ?? "http://127.0.0.1:54321") ?? URL(string: "http://127.0.0.1:54321")!, publicKey: dict["SUPABASE_PUBLISHABLE_KEY"] ?? "", apiVersion: dict["API_VERSION"] ?? "v1", environment: dict["ENVIRONMENT"] ?? "local")
    }
}

enum Multipart {
    static func encode(image: Data, metadata: AnalysisMetadata, boundary: String) throws -> Data {
        guard !image.isEmpty, image.count <= 2 * 1024 * 1024, image.starts(with: [0xFF, 0xD8, 0xFF]) else { throw StylistError.message("The prepared JPEG is unavailable or too large. Choose another photo.") }
        guard metadata.prompt.utf16.count <= 1000 else { throw StylistError.message("Your question must be 1,000 characters or fewer.") }
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"metadata\"\r\n\r\n")
        body.append(try JSONEncoder().encode(metadata))
        append("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"outfit.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n")
        body.append(image)
        append("\r\n--\(boundary)--\r\n")
        return body
    }
}
