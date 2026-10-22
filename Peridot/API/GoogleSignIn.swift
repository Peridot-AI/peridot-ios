import AuthenticationServices
import CryptoKit
import Foundation
import SwiftUI

/// "Continue with Google" without an SDK: Google's sign-in page in a web authentication session,
/// for the iOS OAuth client the server names in `/auth/config` (an iOS client has no secret; the
/// code is redeemed with PKCE). The ID token it returns is issued for that client, which the
/// server accepts through `GOOGLE_IOS_CLIENT_ID`.
enum GoogleSignIn {
    /// Returns the Google ID token, or nil when the user closed the sign-in sheet.
    @MainActor
    static func idToken(clientID: String, session: WebAuthenticationSession) async throws -> String? {
        // iOS clients redirect to their reversed client ID: com.googleusercontent.apps.<id>
        let scheme = clientID.split(separator: ".").reversed().joined(separator: ".")
        let redirectURI = "\(scheme):/oauth2redirect"
        let verifier = randomString()
        let state = randomString()
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]

        let callback: URL
        do {
            callback = try await session.authenticate(using: components.url!, callbackURLScheme: scheme)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return nil
        } catch {
            throw unavailable
        }

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        if value("error") == "access_denied" { return nil }
        guard value("state") == state, let code = value("code") else { throw unavailable }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form([
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        struct Tokens: Decodable { let id_token: String? }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let idToken = (try? JSONDecoder().decode(Tokens.self, from: data))?.id_token
        else { throw unavailable }
        return idToken
    }

    private static var unavailable: APIError { APIError(message: String(localized: "google_unavailable"), status: 0) }

    private static func randomString() -> String {
        base64URL(Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func form(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let encode = { (text: String) in text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text }
        return Data(fields.map { "\(encode($0.key))=\(encode($0.value))" }.joined(separator: "&").utf8)
    }
}
