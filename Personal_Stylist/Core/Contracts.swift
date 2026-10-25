import Foundation

enum StylistError: LocalizedError, Equatable {
    case message(String)
    case api(String, String)
    var errorDescription: String? {
        switch self { case .message(let value), .api(_, let value): return value }
    }
}

// JSON values preserve nulls, optional fields and the original UUID spelling for signed saves.
enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    subscript(_ key: String) -> JSONValue? { if case .object(let v) = self { return v[key] }; return nil }
}

indirect enum WireSchema {
    case object([String: WireSchema], optional: Set<String> = [])
    case array(WireSchema, Int, Int)
    case text(Int, plain: Bool = true, empty: Bool = false)
    case choice(Set<String>), number(Double, Double, step: Double), bool, uuid
    case nullable(WireSchema)

    func validate(_ value: JSONValue) throws {
        let invalid = StylistError.message("The response could not be validated. Start a new analysis only if you want another attempt.")
        switch (self, value) {
        case let (.object(fields, optional), .object(values)):
            guard Set(values.keys).isSubset(of: Set(fields.keys)), Set(fields.keys).subtracting(optional).isSubset(of: Set(values.keys)) else { throw invalid }
            for (key, value) in values { try fields[key]!.validate(value) }
        case let (.array(schema, min, max), .array(values)):
            guard (min...max).contains(values.count) else { throw invalid }
            try values.forEach { try schema.validate($0) }
        case let (.text(max, plain, empty), .string(s)):
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard s.utf16.count <= max, empty || !trimmed.isEmpty else { throw invalid }
            if plain && s.range(of: "</?[a-z][^>]*>|https?://", options: [.regularExpression, .caseInsensitive]) != nil { throw invalid }
        case let (.choice(choices), .string(s)): guard choices.contains(s) else { throw invalid }
        case let (.number(min, max, step), .number(n)):
            guard n.isFinite, n >= min, n <= max, (n / step).rounded() == n / step else { throw invalid }
        case (.bool, .bool): break
        case (.uuid, .string(let s)): guard UUID(uuidString: s) != nil else { throw invalid }
        case (.nullable, .null): break
        case let (.nullable(schema), value): try schema.validate(value)
        default: throw invalid
        }
    }
}

enum Contracts {
    static let policyVersion = "2026-09-01"
    static let criterionIDs: Set<String> = ["silhouette", "colour", "coherence", "finishing", "intent"]
    static let preferences = WireSchema.object([
        "desiredStyle": .text(160), "constraints": .array(.text(160), 0, 10)
    ], optional: ["desiredStyle", "constraints"])
    static let criterion = WireSchema.object([
        "id": .choice(criterionIDs), "applicable": .bool, "score": .nullable(.number(0, 5, step: 1)),
        "observation": .text(500), "explanation": .text(700)
    ])
    static let report = WireSchema.object([
        "schemaVersion": .number(1, 1, step: 1), "runId": .uuid,
        "status": .choice(["complete", "partial"]), "summary": .text(700),
        "overallScore": .nullable(.number(0, 10, step: 0.5)), "verdict": .nullable(.choice(["works_well", "could_improve"])),
        "criteria": .array(criterion, 5, 5), "strengths": .array(.text(500), 0, 5),
        "suggestions": .array(.object(["observation": .text(500), "action": .text(500), "reason": .text(500), "kind": .choice(["restyle", "remove", "care", "swap", "add"])], optional: ["kind"]), 0, 5),
        "limitations": .array(.text(500), 0, 6),
        "versions": .object(["agent": .text(100), "skill": .text(100), "rubric": .text(100), "model": .text(150)])
    ])
    static let saved = WireSchema.object(["id": .uuid, "created_at": .text(200, plain: false), "report": report])
    static let history = WireSchema.object(["items": .array(saved, 0, 20), "nextCursor": .nullable(.text(2000, plain: false, empty: true))])
    static let bootstrap = WireSchema.object([
        "analysisMode": .choice(["mock", "live"]), "dailyQuotaExempt": .bool, "profile": preferences,
        "policyVersion": .text(100, plain: false), "consentAccepted": .bool,
        "features": .object(["outfit": .bool]), "remainingQuota": .number(0, 3, step: 1), "betaAccess": .bool
    ], optional: ["analysisMode", "dailyQuotaExempt"])

    static func decode<T: Decodable>(_ type: T.Type, data: Data, schema: WireSchema) throws -> T {
        do {
            try schema.validate(JSONDecoder().decode(JSONValue.self, from: data))
            return try JSONDecoder().decode(type, from: data)
        } catch { throw StylistError.message("The service returned an invalid response. Please try again.") }
    }
}

struct Preferences: Codable, Equatable, Sendable {
    var desiredStyle: String?
    var constraints: [String]?
    func validated() throws -> Preferences {
        try Contracts.preferences.validate(JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(self)))
        return self
    }
}
struct Bootstrap: Codable, Sendable {
    struct Features: Codable, Sendable { let outfit: Bool }
    let analysisMode: String?
    let dailyQuotaExempt: Bool?
    let profile: Preferences
    let policyVersion: String
    let consentAccepted: Bool
    let features: Features
    let remainingQuota: Int
    let betaAccess: Bool
    var hasConsent: Bool { consentAccepted && policyVersion == Contracts.policyVersion }
    var allowance: String { dailyQuotaExempt == true ? "Unlimited daily analyses · test account" : "\(remainingQuota) of 3 daily analyses remaining" }
    var analysisBlock: String? {
        if !hasConsent { return "Accept the current AI-processing policy to continue." }
        if !betaAccess { return "Your invitation is awaiting activation." }
        if dailyQuotaExempt != true && remainingQuota == 0 { return "You have used all 3 daily analyses. Your allowance resets at midnight UTC." }
        if !features.outfit { return "Analysis is currently paused." }
        return nil
    }
}
struct Criterion: Codable, Identifiable, Sendable {
    let id: String
    let applicable: Bool
    let score: Int?
    let observation: String
    let explanation: String
}
struct Suggestion: Codable, Sendable { let observation: String; let action: String; let reason: String; let kind: String? }
struct OutfitReport: Decodable, Sendable {
    let schemaVersion: Int
    let runId: String
    let status: String
    let summary: String
    let overallScore: Double?
    let verdict: String?
    let criteria: [Criterion]
    let strengths: [String]
    let suggestions: [Suggestion]
    let limitations: [String]
    let versions: [String: String]
    func validate() throws {
        guard Set(criteria.map(\.id)) == Contracts.criterionIDs,
              criteria.allSatisfy({ $0.applicable || $0.score == nil }) else {
            throw StylistError.message("The assessment criteria could not be validated.")
        }
    }
    var rating: String { overallScore.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—" }
    var verdictLabel: String {
        switch verdict { case "works_well": return "Works well"; case "could_improve": return "Could improve"; default: return "Not enough visible detail to rate" }
    }
}
struct SavedReport: Decodable, Identifiable, Sendable {
    let id: String
    let created_at: String
    let report: OutfitReport
    var dateLabel: String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: created_at) ?? ISO8601DateFormatter().date(from: created_at)
        return date?.formatted(date: .abbreviated, time: .omitted) ?? created_at
    }
}
struct HistoryPage: Decodable, Sendable { let items: [SavedReport]; let nextCursor: String? }
struct AnalysisResult: Sendable {
    let report: OutfitReport?
    let rawReport: JSONValue?
    let receipt: String?
    let instructions: [String]
    static func decode(_ data: Data) throws -> AnalysisResult {
        let raw = try JSONDecoder().decode(JSONValue.self, from: data)
        if raw["kind"] == .string("report") {
            try WireSchema.object(["kind": .choice(["report"]), "report": Contracts.report, "receipt": .text(1500, plain: false, empty: true)]).validate(raw)
            let report = try JSONDecoder().decode(OutfitReport.self, from: JSONEncoder().encode(raw["report"]!))
            try report.validate()
            guard case .string(let receipt) = raw["receipt"] else { throw StylistError.message("Missing save receipt.") }
            return AnalysisResult(report: report, rawReport: raw["report"], receipt: receipt, instructions: [])
        }
        try WireSchema.object(["kind": .choice(["retake"]), "issues": .array(.choice(["no_outfit", "multiple_people", "too_dark", "blurred", "too_cropped", "unsupported_content"]), 1, 6), "instructions": .array(.text(350), 1, 6)]).validate(raw)
        guard case .array(let items) = raw["instructions"] else { throw StylistError.message("Missing retake instructions.") }
        return AnalysisResult(report: nil, rawReport: nil, receipt: nil, instructions: items.compactMap { if case .string(let s) = $0 { return s }; return nil })
    }
    func saveBody() throws -> Data {
        guard let rawReport, let receipt else { throw StylistError.message("There is no report to save.") }
        return try JSONEncoder().encode(JSONValue.object(["report": rawReport, "receipt": .string(receipt)]))
    }
}

enum IntentPreset: String, CaseIterable, Identifiable, Sendable {
    case general, everyday, work, date, eveningOut, formalEvent, morePolished, moreExpressive, custom
    var id: Self { self }
    var label: String {
        switch self {
        case .general: return "General"; case .everyday: return "Everyday"; case .work: return "Work"
        case .date: return "Date"; case .eveningOut: return "Evening out"; case .formalEvent: return "Formal event"
        case .morePolished: return "More polished"; case .moreExpressive: return "More expressive"; case .custom: return "Custom"
        }
    }
    func context(custom: String) throws -> [String: String] {
        switch self {
        case .general: return [:]
        case .everyday: return ["occasion": "Everyday activities"]
        case .work: return ["occasion": "Work, without assuming a specific workplace dress code"]
        case .date: return ["occasion": "A date, without assuming venue or formality"]
        case .eveningOut: return ["occasion": "An evening out"]
        case .formalEvent: return ["occasion": "A formal event, without assuming black tie"]
        case .morePolished: return ["desiredStyle": "A more polished presentation"]
        case .moreExpressive: return ["desiredStyle": "A more expressive presentation"]
        case .custom:
            let s = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            do { try WireSchema.text(160).validate(.string(s)) } catch { throw StylistError.message("Enter a plain-text intent of 1–160 characters.") }
            return ["desiredStyle": s]
        }
    }
}
enum StylistTier: String, Codable, CaseIterable, Sendable { case everyday, expert
    var label: String { self == .everyday ? "Everyday" : "Expert" }
}
enum AnalysisDepth: String, Codable, CaseIterable, Sendable { case quick, deep
    var label: String { self == .quick ? "Quick" : "Deep" }
}
struct AnalysisSelection: Equatable, Sendable {
    var stylistTier: StylistTier = .everyday
    var analysisDepth: AnalysisDepth = .quick
    var label: String { "\(stylistTier.label) · \(analysisDepth.label)" }
}
struct AnalysisOptions: Decodable, Sendable {
    struct Profile: Decodable, Sendable {
        let stylistTier: StylistTier
        let analysisDepth: AnalysisDepth
        let enabled: Bool
        let unavailableReason: String?
    }
    let profiles: [Profile]
    var legacy = false
    enum CodingKeys: String, CodingKey { case profiles }
    static let legacyOptions = AnalysisOptions(profiles: StylistTier.allCases.flatMap { tier in AnalysisDepth.allCases.map { depth in
        Profile(stylistTier: tier, analysisDepth: depth, enabled: tier == .everyday && depth == .quick, unavailableReason: "This server supports Everyday Quick only.")
    } }, legacy: true)
    func block(for selection: AnalysisSelection) -> String? {
        guard let profile = profiles.first(where: { $0.stylistTier == selection.stylistTier && $0.analysisDepth == selection.analysisDepth }), profile.enabled else {
            return profiles.first(where: { $0.stylistTier == selection.stylistTier && $0.analysisDepth == selection.analysisDepth })?.unavailableReason ?? "This analysis option is unavailable."
        }
        return nil
    }
    static func decode(_ data: Data) throws -> AnalysisOptions {
        let schema = WireSchema.object(["profiles": .array(.object(["stylistTier": .choice(["everyday", "expert"]), "analysisDepth": .choice(["quick", "deep"]), "enabled": .bool, "unavailableReason": .nullable(.text(200))]), 4, 4)])
        let value = try Contracts.decode(Self.self, data: data, schema: schema)
        guard Set(value.profiles.map { "\($0.stylistTier.rawValue):\($0.analysisDepth.rawValue)" }).count == 4 else { throw StylistError.message("Invalid analysis options.") }
        return value
    }
}
struct AnalysisMetadata: Encodable, Sendable {
    let schemaVersion = 1
    let prompt: String
    let context: [String: String]
    var stylistTier: StylistTier? = nil
    var analysisDepth: AnalysisDepth? = nil
}
