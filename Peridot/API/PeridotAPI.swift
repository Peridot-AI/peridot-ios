import Foundation

/// The Peridot REST API (the same one the website, desktop app and CLI use).
struct PeridotAPI: Sendable {
    var baseURL: URL = Config.apiURL
    var token: String?

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        // Answers stream for a long time; this only limits the silence between chunks
        config.timeoutIntervalForRequest = 300
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private static let decoder = JSONDecoder()

    // MARK: Auth

    func login(email: String, password: String) async throws -> AuthResponse {
        try await send("POST", "/auth/login", body: ["email": email, "password": password])
    }

    /// Signs in with a Google ID token (from `GoogleSignIn`).
    func googleLogin(idToken: String) async throws -> AuthResponse {
        try await send("POST", "/auth/google", body: ["idToken": idToken])
    }

    func authConfig() async throws -> AuthConfig {
        try await send("GET", "/auth/config")
    }

    func me() async throws -> MeResponse {
        try await send("GET", "/auth/me")
    }

    // MARK: Models

    func models() async throws -> [Model] {
        let response: ModelsResponse = try await send("GET", "/models")
        return response.models
    }

    // MARK: Chat history (signed in only)

    func conversations() async throws -> [Conversation] {
        let response: ConversationsResponse = try await send("GET", "/conversations")
        return response.conversations
    }

    func conversation(_ id: Int) async throws -> ConversationResponse {
        try await send("GET", "/conversations/\(id)")
    }

    func createConversation(title: String) async throws -> Conversation {
        let response: CreatedConversation = try await send("POST", "/conversations", body: ["title": title])
        return response.conversation
    }

    func addMessages(_ id: Int, _ messages: [APIMessage]) async throws {
        let body: [String: Any] = ["messages": messages.map { ["role": $0.role, "content": $0.content] }]
        _ = try await data("POST", "/conversations/\(id)/messages", body: body)
    }

    func renameConversation(_ id: Int, title: String) async throws {
        _ = try await data("PATCH", "/conversations/\(id)", body: ["title": title])
    }

    func deleteConversation(_ id: Int) async throws {
        _ = try await data("DELETE", "/conversations/\(id)")
    }

    // MARK: Sharing (a public, read-only copy of a chat)

    func shareStatus(_ id: Int) async throws -> ShareInfo? {
        let response: ShareResponse = try await send("GET", "/conversations/\(id)/share")
        return response.share
    }

    func share(_ id: Int) async throws -> ShareInfo {
        let response: ShareResponse = try await send("POST", "/conversations/\(id)/share", body: [:])
        guard let share = response.share else { throw APIError(message: "Could not share this chat", status: 500) }
        return share
    }

    func stopSharing(_ id: Int) async throws {
        _ = try await data("DELETE", "/conversations/\(id)/share")
    }

    // MARK: Invites

    func referrals() async throws -> ReferralStats {
        try await send("GET", "/referrals")
    }

    // MARK: Plans (the payment itself happens on Stripe's page in the browser)

    func checkoutConfig() async throws -> CheckoutConfig {
        try await send("GET", "/checkout/config")
    }

    func checkoutOffer() async throws -> CheckoutOffer {
        try await send("GET", "/checkout/offer")
    }

    /// Stripe's checkout page for the plan; the consents were given in the app.
    func checkoutSession(plan: String, lang: String) async throws -> URL {
        let response: CheckoutSession = try await send("POST", "/checkout/session", body: [
            "plan": plan,
            "lang": lang,
            "consent": ["terms": true, "immediateStart": true],
        ])
        guard let url = URL(string: response.url) else { throw APIError(message: "Could not start the payment", status: 502) }
        return url
    }

    // MARK: Streaming chat

    /// Streams one answer as text chunks. Ending the iteration (or cancelling the task that
    /// iterates) closes the connection, which also stops the model on the server.
    func stream(messages: [APIMessage], model: String?, effort: Effort) -> AsyncThrowingStream<String, Error> {
        var body: [String: Any] = [
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "effort": effort.rawValue,
        ]
        if let model { body["model"] = model }
        let request = makeRequest("POST", "/chat/stream", body: body, accept: "text/event-stream")

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await Self.session.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(status) else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw APIError.from(status: status, data: data)
                    }

                    var parser = SSEParser()
                    /// Returns true when the stream says it is done.
                    func handle(_ event: SSEEvent?) throws -> Bool {
                        guard let event else { return false }
                        switch event.event {
                        case "error":
                            let message = (try? Self.decoder.decode(StreamChunk.self, from: Data(event.data.utf8)))?.error
                            throw APIError(message: cleanError(message) ?? "Streaming error", status: status)
                        case "done":
                            return true
                        case "message":
                            if let chunk = try Self.decoder.decode(StreamChunk.self, from: Data(event.data.utf8)).chunk {
                                continuation.yield(chunk)
                            }
                        default:
                            break
                        }
                        return false
                    }

                    // Lines are split by hand: `bytes.lines` skips the blank lines that end events
                    var line = Data()
                    var done = false
                    for try await byte in bytes {
                        if byte == UInt8(ascii: "\n") {
                            if line.last == UInt8(ascii: "\r") { line.removeLast() }
                            let text = String(decoding: line, as: UTF8.self)
                            line.removeAll(keepingCapacity: true)
                            if try handle(parser.feed(text)) { done = true; break }
                        } else {
                            line.append(byte)
                        }
                    }
                    if !done {
                        if !line.isEmpty { _ = try handle(parser.feed(String(decoding: line, as: UTF8.self))) }
                        _ = try handle(parser.finish())
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private struct StreamChunk: Decodable {
        let chunk: String?
        let error: String?
    }

    // MARK: Plumbing

    private func makeRequest(_ method: String, _ path: String, body: [String: Any]? = nil, accept: String = "application/json") -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(String(path.dropFirst())))
        request.httpMethod = method
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func data(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> Data {
        let (data, response) = try await Self.session.data(for: makeRequest(method, path, body: body))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw APIError.from(status: status, data: data) }
        return data
    }

    private func send<T: Decodable>(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> T {
        try Self.decoder.decode(T.self, from: try await data(method, path, body: body))
    }
}
