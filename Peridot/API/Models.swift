import Foundation

/// A chat message as the API stores it. The assistant's role is "model".
struct APIMessage: Codable, Equatable, Sendable {
    let role: String
    let content: String
}

struct User: Codable, Equatable, Sendable {
    let id: Int
    let email: String
    var name: String?
    var role: String?
    var avatar: String?
    var plan: String?

    var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        return email
    }
}

struct AuthResponse: Decodable, Sendable {
    let token: String
    let user: User
}

/// Public sign-in config; the iOS app signs in to Google with `googleIosClientId`.
struct AuthConfig: Decodable, Sendable {
    let googleIosClientId: String?
}

struct Limits: Decodable, Equatable, Sendable {
    var plan: String = "free"
    var unlimited: Bool = false
    var monthlyPercent: Int = 0
    var dailyUsed: Int = 0
    var dailyLimit: Int = 0

    enum CodingKeys: String, CodingKey { case plan, unlimited, monthlyPercent, dailyUsed, dailyLimit }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plan = try c.decodeIfPresent(String.self, forKey: .plan) ?? "free"
        unlimited = try c.decodeIfPresent(Bool.self, forKey: .unlimited) ?? false
        monthlyPercent = try c.decodeIfPresent(Int.self, forKey: .monthlyPercent) ?? 0
        dailyUsed = try c.decodeIfPresent(Int.self, forKey: .dailyUsed) ?? 0
        dailyLimit = try c.decodeIfPresent(Int.self, forKey: .dailyLimit) ?? 0
    }
}

struct MeResponse: Decodable, Sendable {
    let user: User
    let limits: Limits?
}

struct Model: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    var badge: String?
    var desc: String?
    var locked: Bool?

    var isLocked: Bool { locked ?? false }
}

struct ModelsResponse: Decodable, Sendable {
    let models: [Model]
}

struct Conversation: Decodable, Identifiable, Equatable, Sendable {
    let id: Int
    var title: String
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title
        case updatedAt = "updated_at"
    }
}

struct ConversationsResponse: Decodable, Sendable {
    let conversations: [Conversation]
}

struct ConversationResponse: Decodable, Sendable {
    let conversation: Conversation
    let messages: [APIMessage]
}

struct CreatedConversation: Decodable, Sendable {
    let conversation: Conversation
}

/// Reasoning effort; the server caps it to what the plan allows.
enum Effort: String, CaseIterable, Identifiable, Sendable {
    case low = "Low", medium = "Medium", high = "High"
    var id: String { rawValue }
}

/// An error from the API, with the server's message (already user-facing) and code.
struct APIError: LocalizedError, Sendable {
    let message: String
    let status: Int
    var code: String?

    var errorDescription: String? { message }

    static func from(status: Int, data: Data) -> APIError {
        struct Body: Decodable { let error: String?; let code: String? }
        let body = try? JSONDecoder().decode(Body.self, from: data)
        return APIError(message: cleanError(body?.error) ?? "Request failed (\(status))", status: status, code: body?.code)
    }
}

/// Provider errors sometimes arrive as raw JSON ({"error":{"message":…}}); keep just the message.
func cleanError(_ message: String?) -> String? {
    guard let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    guard let start = message.firstIndex(of: "{"),
          let data = String(message[start...]).data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return message }
    if let inner = object["error"] as? [String: Any], let text = inner["message"] as? String { return text }
    if let text = object["error"] as? String { return text }
    if let text = object["message"] as? String { return text }
    return message
}
