import AuthenticationServices
import CryptoKit
import UIKit

/// One tap PKCE sign in for OpenRouter. The exchanged key is still stored in
/// the device Keychain and is used by the existing OpenAI compatible adapter.
@MainActor
final class OpenRouterOAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func connect() async throws -> String {
        let transaction = OpenRouterAuthorization()
        let url = try transaction.authorizationURL()

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let authSession = ASWebAuthenticationSession(url: url, callbackURLScheme: "prompti") { [weak self] callbackURL, error in
                self?.session = nil
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: OAuthError.missingCallback)
                }
            }
            authSession.presentationContextProvider = self
            authSession.prefersEphemeralWebBrowserSession = false
            self.session = authSession
            guard authSession.start() else {
                self.session = nil
                continuation.resume(throwing: OAuthError.couldNotStart)
                return
            }
        }

        let code = try transaction.code(from: callback)
        return try await transaction.exchange(code: code)
    }

    func cancel() { session?.cancel(); session = nil }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
    }

}

/// Keep PKCE and callback validation independent from browser presentation.
struct OpenRouterAuthorization: Sendable {
    let verifier: String
    let state: String

    init(verifier: String = Self.randomString(length: 64), state: String = Self.randomString(length: 32)) {
        self.verifier = verifier
        self.state = state
    }

    var challenge: String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func authorizationURL(manual: Bool = false) throws -> URL {
        var components = URLComponents(string: "https://openrouter.ai/auth")!
        components.queryItems = [
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "key_label", value: "Prompti iOS")
        ]
        if !manual {
            components.queryItems?.append(URLQueryItem(name: "callback_url", value: "prompti://oauth/openrouter?state=\(state)"))
        }
        guard let url = components.url else { throw OAuthError.invalidAuthorizationURL }
        return url
    }

    func code(from callback: URL) throws -> String {
        guard callback.scheme == "prompti", callback.host == "oauth", callback.path == "/openrouter",
              callback.user == nil, callback.password == nil, callback.port == nil,
              let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
              !items.contains(where: { $0.name == "error" }),
              items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == state,
              items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw OAuthError.authorizationDenied
        }
        return code
    }

    func exchangeRequest(code: String) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/auth/keys")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "code": code, "code_verifier": verifier, "code_challenge_method": "S256"
        ])
        return request
    }

    func exchange(code: String) async throws -> String {
        let session = URLSession(configuration: .ephemeral, delegate: OAuthRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: exchangeRequest(code: code))
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode, data.count < 64_000 else {
            throw OAuthError.exchangeFailed
        }
        let payload = try JSONDecoder().decode(KeyPayload.self, from: data)
        guard !payload.key.isEmpty else { throw OAuthError.exchangeFailed }
        return payload.key
    }

    private struct KeyPayload: Decodable { let key: String }

    static func randomString(length: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
    }
}

private final class OAuthRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum OAuthError: LocalizedError {
    case invalidAuthorizationURL
    case missingCallback
    case couldNotStart
    case authorizationDenied
    case exchangeFailed

    var errorDescription: String? {
        switch self {
        case .invalidAuthorizationURL, .couldNotStart: String(localized: "Unable to open secure sign in. Try again.")
        case .missingCallback, .authorizationDenied: String(localized: "Sign in was cancelled or not approved.")
        case .exchangeFailed: String(localized: "OpenRouter could not finish connecting this device. Try signing in again.")
        }
    }
}
