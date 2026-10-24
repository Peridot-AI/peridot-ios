import Foundation
import Observation
import AuthenticationServices
import SwiftUI

enum Role { case user, model }

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    var text: String
    var streaming = false
    var error: String?
}

/// Everything the app shows: the account, the open chat (with the answer that is streaming),
/// the chat history and the model choice. Mirrors ChatViewModel in the Android app.
@MainActor
@Observable
final class ChatStore {
    private(set) var user: User?
    private(set) var limits: Limits?
    private(set) var messages: [ChatMessage] = []
    private(set) var streaming = false
    private(set) var models: [Model] = []
    private(set) var model: String?
    private(set) var effort: Effort
    private(set) var conversations: [Conversation] = []
    private(set) var conversationID: Int?
    private(set) var loadingConversation = false
    /// A one-off message for an alert.
    var notice: String?
    /// The open chat's public link, if it is shared
    private(set) var share: ShareInfo?
    private(set) var referrals: ReferralStats?
    private(set) var plans: CheckoutConfig?
    private(set) var offer: CheckoutOffer?
    /// A payment was started in the browser: the account is reloaded until the plan changes
    private(set) var awaitingPlan = false

    private(set) var authBusy = false
    var authError: String?

    var signedIn: Bool { user != nil }
    var currentModel: Model? { models.first { $0.id == model } }

    private var token: String?
    private var api: PeridotAPI { PeridotAPI(token: token) }
    private var streamTask: Task<Void, Never>?

    /// Every chat on screen gets a serial number; work that finishes after the user moved to
    /// another chat (a save, the end of a stream) checks it and leaves the new chat alone.
    private var chatSerial = 0
    private var savedAs: [Int: Int] = [:]
    /// Saves run one after another, so the first one can create the conversation for the rest.
    private var saveQueue: Task<Void, Never>?

    private let defaults = UserDefaults.standard

    init() {
        token = Keychain.token
        effort = Effort(rawValue: UserDefaults.standard.string(forKey: "effort") ?? "") ?? .medium
        if token != nil {
            // Show the account straight away; /auth/me fills in the rest
            user = User(id: 0, email: "")
            refreshAccount()
            loadConversations()
        }
        loadModels()
    }

    // MARK: Account

    func signIn(email: String, password: String) async -> Bool {
        let api = api
        return await authenticate { try await api.login(email: email.trimmingCharacters(in: .whitespaces), password: password) }
    }

    /// Signs in with Google through a web authentication session (see `GoogleSignIn`).
    func signInWithGoogle(using session: WebAuthenticationSession) async -> Bool {
        let api = api
        return await authenticate {
            guard let clientID = try await api.authConfig().googleIosClientId, !clientID.isEmpty else {
                throw APIError(message: String(localized: "google_unavailable"), status: 503)
            }
            guard let idToken = try await GoogleSignIn.idToken(clientID: clientID, session: session) else { return nil }
            return try await api.googleLogin(idToken: idToken)
        }
    }

    /// Runs a sign-in; `call` returns nil when the user backed out, which is not an error.
    private func authenticate(_ call: () async throws -> AuthResponse?) async -> Bool {
        guard !authBusy else { return false }
        authBusy = true
        authError = nil
        defer { authBusy = false }
        do {
            guard let result = try await call() else { return false }
            token = result.token
            Keychain.token = result.token
            user = result.user
            refreshAccount()
            loadModels()
            loadConversations()
            return true
        } catch {
            authError = describe(error)
            return false
        }
    }

    func signOut(expired: Bool = false) {
        token = nil
        Keychain.token = nil
        startOver()
        user = nil
        limits = nil
        conversations = []
        if expired { notice = String(localized: "session_expired") }
        loadModels()
    }

    func refreshAccount() {
        guard token != nil else { return }
        Task {
            do {
                let me = try await api.me()
                user = me.user
                limits = me.limits
                if awaitingPlan, (me.user.plan ?? "free") != "free" {
                    awaitingPlan = false
                    notice = String(localized: "plan_active")
                }
            } catch {
                if !expiredSession(error), user?.email.isEmpty ?? true {
                    // Offline at start-up: stay signed in, the next request will tell
                    notice = describe(error)
                }
            }
        }
    }

    // MARK: Models

    func loadModels() {
        Task {
            guard let list = try? await api.models() else { return } // the server then picks its default
            let saved = defaults.string(forKey: "model")
            let usable = list.filter { !$0.isLocked }
            models = list
            model = usable.first { $0.id == saved }?.id ?? usable.first?.id ?? model
        }
    }

    func select(_ model: Model) {
        guard !model.isLocked else { return }
        defaults.set(model.id, forKey: "model")
        self.model = model.id
    }

    func select(_ effort: Effort) {
        defaults.set(effort.rawValue, forKey: "effort")
        self.effort = effort
    }

    // MARK: Chat history

    func loadConversations() {
        guard token != nil else { return }
        Task {
            do {
                conversations = try await api.conversations()
            } catch {
                _ = expiredSession(error)
            }
        }
    }

    func newChat() { startOver() }

    private func startOver() {
        streamTask?.cancel()
        streamTask = nil
        chatSerial += 1
        messages = []
        conversationID = nil
        streaming = false
        loadingConversation = false
        share = nil
    }

    // MARK: Sharing

    func loadShare() {
        guard let id = conversationID else { return }
        Task {
            let share = try? await api.shareStatus(id)
            if conversationID == id { self.share = share }
        }
    }

    /// Makes (or refreshes) the public copy of the open chat and returns its link.
    func shareChat() async -> URL? {
        guard let id = conversationID else { return nil }
        do {
            let share = try await api.share(id)
            self.share = share
            return URL(string: shareLink(share.id))
        } catch {
            if !expiredSession(error) { notice = describe(error) }
            return nil
        }
    }

    func stopSharing() {
        guard let id = conversationID else { return }
        Task {
            do {
                try await api.stopSharing(id)
                share = nil
                notice = String(localized: "sharing_stopped")
            } catch {
                if !expiredSession(error) { notice = describe(error) }
            }
        }
    }

    // MARK: Invites and plans

    func loadReferrals() {
        guard token != nil else { return }
        Task { if let r = try? await api.referrals() { referrals = r } }
    }

    func loadPlans() {
        Task {
            do {
                plans = try await api.checkoutConfig()
                offer = token != nil ? (try? await api.checkoutOffer()) : nil
            } catch {
                notice = describe(error)
            }
        }
    }

    /// Stripe's checkout page for the plan, to open in the browser; back in the app the account is reloaded.
    func checkout(plan: String) async -> URL? {
        do {
            let url = try await api.checkoutSession(plan: plan, lang: Locale.current.language.languageCode?.identifier ?? "en")
            awaitingPlan = true
            return url
        } catch {
            if !expiredSession(error) { notice = describe(error) }
            return nil
        }
    }

    func open(_ conversation: Conversation) {
        if conversation.id == conversationID, !loadingConversation { return }
        startOver()
        let serial = chatSerial
        savedAs[serial] = conversation.id
        conversationID = conversation.id
        loadingConversation = true
        Task {
            do {
                let loaded = try await api.conversation(conversation.id)
                guard serial == chatSerial else { return }
                messages = loaded.messages.map { ChatMessage(role: $0.role == "user" ? .user : .model, text: $0.content) }
                loadingConversation = false
            } catch {
                guard serial == chatSerial else { return }
                loadingConversation = false
                if !expiredSession(error) { notice = describe(error) }
            }
        }
    }

    func rename(_ conversation: Conversation, to title: String) {
        let clean = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !clean.isEmpty, clean != conversation.title else { return }
        if let i = conversations.firstIndex(where: { $0.id == conversation.id }) { conversations[i].title = clean }
        Task {
            do {
                try await api.renameConversation(conversation.id, title: clean)
            } catch {
                if !expiredSession(error) { notice = describe(error) }
                loadConversations()
            }
        }
    }

    func delete(_ conversation: Conversation) {
        if conversation.id == conversationID { startOver() }
        conversations.removeAll { $0.id == conversation.id }
        Task {
            do {
                try await api.deleteConversation(conversation.id)
            } catch {
                if !expiredSession(error) { notice = describe(error) }
                loadConversations()
            }
        }
    }

    // MARK: Sending

    /// Returns false when nothing was sent (empty text, or an answer is still coming).
    func send(_ text: String) -> Bool {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !streaming, !loadingConversation else { return false }
        let history = messages.filter { $0.error == nil && !$0.text.isEmpty }
        stream(history + [ChatMessage(role: .user, text: question)], question: question)
        return true
    }

    /// Asks again after a failed answer (the failed one is dropped).
    func retry() {
        guard !streaming, let last = messages.last, last.role == .model, last.error != nil else { return }
        let history = messages.dropLast().filter { $0.error == nil && !$0.text.isEmpty }
        guard let question = history.last(where: { $0.role == .user })?.text else { return }
        stream(Array(history), question: question)
    }

    func stop() {
        streamTask?.cancel()
    }

    private func stream(_ history: [ChatMessage], question: String) {
        let serial = chatSerial
        let answer = ChatMessage(role: .model, text: "", streaming: true)
        messages = history + [answer]
        streaming = true
        let request = history.map { APIMessage(role: $0.role == .user ? "user" : "model", content: $0.text) }
        let chunks = api.stream(messages: request, model: model, effort: effort)

        streamTask = Task {
            var text = ""
            var failure: String?
            do {
                for try await chunk in chunks {
                    text += chunk
                    update(answer.id) { $0.text = text }
                }
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                failure = expiredSession(error) ? nil : describe(error)
            }
            update(answer.id) { $0.streaming = false; $0.error = failure }
            if serial == chatSerial { streaming = false }
            // Like the CLI, an answer stopped half-way is kept and saved; a failed one is not,
            // so "Retry" doesn't leave the question in the history twice
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, failure == nil, token != nil {
                save(serial: serial, question: question, answer: text)
            }
            if token != nil { refreshAccount() }
        }
    }

    private func update(_ id: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[i])
    }

    /// Saves one exchange to the account's history, creating the conversation on the first one.
    private func save(serial: Int, question: String, answer: String) {
        let previous = saveQueue
        let api = self.api
        saveQueue = Task {
            await previous?.value
            do {
                let id: Int
                if let known = savedAs[serial] {
                    id = known
                } else {
                    let title = String(question.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(60))
                    id = try await api.createConversation(title: title).id
                    savedAs[serial] = id
                    if serial == chatSerial { conversationID = id }
                }
                try await api.addMessages(id, [APIMessage(role: "user", content: question), APIMessage(role: "model", content: answer)])
                loadConversations()
            } catch {
                // History is a convenience: a failed save never gets in the way of the chat
            }
        }
    }

    // MARK: Errors

    /// Signs out when the server says the token is no longer valid. Returns true if it did.
    private func expiredSession(_ error: Error) -> Bool {
        if let error = error as? APIError, error.status == 401, token != nil {
            signOut(expired: true)
            return true
        }
        return false
    }

    private func describe(_ error: Error) -> String {
        if let error = error as? APIError { return error.message }
        if error is URLError { return String(localized: "error_network") }
        return String(localized: "error_generic")
    }
}
