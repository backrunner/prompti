import Foundation
import Testing
@testable import Prompti

@Suite("OAuth and credential isolation")
struct OAuthTests {
    @Test("S256 matches RFC 7636's published test vector")
    func challenge() {
        let request = OpenRouterAuthorization(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", state: "test")
        #expect(request.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test("Browser URL sends the challenge, never the verifier")
    func authorization() throws {
        let request = OpenRouterAuthorization()
        let url = try request.authorizationURL()
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first(where: { $0.name == "code_challenge_method" })?.value == "S256")
        #expect(!url.absoluteString.contains(request.verifier))
        let callback = try #require(items.first(where: { $0.name == "callback_url" })?.value)
        #expect(callback.contains(request.state))
        #expect(try !request.authorizationURL(manual: true).absoluteString.contains("callback_url"))
    }

    @Test("Both browser flows enter sign-in and preserve the complete PKCE redirect", arguments: [false, true])
    func signInEntry(manual: Bool) throws {
        let authorization = OpenRouterAuthorization()
        let url = try authorization.signInURL(manual: manual)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "openrouter.ai")
        #expect(components.path == "/sign-in")
        let items = try #require(components.queryItems)
        #expect(items.count == 1)
        #expect(items.first?.name == "redirect_url")
        let redirect = try #require(items.first?.value)
        #expect(redirect == (try authorization.authorizationURL(manual: manual)).absoluteString)
        #expect(!url.absoluteString.contains(authorization.verifier))

        let redirectItems = try #require(URLComponents(string: redirect)?.queryItems)
        let callback = redirectItems.first(where: { $0.name == "callback_url" })?.value
        #expect(callback == (manual ? nil : "prompti://oauth/openrouter?state=\(authorization.state)"))
        #expect(redirectItems.first(where: { $0.name == "code_challenge" })?.value == authorization.challenge)
        #expect(redirectItems.first(where: { $0.name == "code_challenge_method" })?.value == "S256")
    }

    @Test("Callbacks must match the active state and exact redirect")
    func callbacks() throws {
        let request = OpenRouterAuthorization(state: "expected")
        #expect(try request.code(from: URL(string: "prompti://oauth/openrouter?state=expected&code=approved")!) == "approved")
        for url in [
            "prompti://oauth/openrouter?code=approved",
            "prompti://oauth/openrouter?state=wrong&code=approved",
            "prompti://oauth/openrouter?state=expected&state=other&code=approved",
            "prompti://oauth/openrouter?state=expected&code=one&code=two",
            "prompti://oauth/openrouter?state=expected&code=",
            "prompti://oauth/openrouter?state=expected&code=approved&error=denied",
            "https://oauth/openrouter?state=expected&code=approved",
            "prompti://other/openrouter?state=expected&code=approved"
        ] {
            #expect(throws: OAuthError.self) { try request.code(from: URL(string: url)!) }
        }
    }

    @Test("Code exchange uses the original verifier and the official endpoint")
    func exchangeContract() throws {
        let authorization = OpenRouterAuthorization()
        let request = try authorization.exchangeRequest(code: "one-use-code")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/auth/keys")
        #expect(request.httpMethod == "POST")
        #expect(body["code_verifier"] == authorization.verifier)
        #expect(body["code_challenge_method"] == "S256")
    }

    @Test("Credentials are isolated by protocol, server, port and tenant path")
    func credentialIsolation() {
        let source = ProviderConfiguration(kind: .openAIChat, baseURL: "https://gateway.example.com/team-a", model: "a")
        var same = source
        same.model = "b"
        #expect(source.credentialScope == same.credentialScope)
        same.baseURL = "https://GATEWAY.example.com/team-a/"
        #expect(source.credentialScope == same.credentialScope)
        for url in ["https://elsewhere.example.com/team-a", "https://gateway.example.com/team-b", "https://gateway.example.com:8443/team-a"] {
            same.baseURL = url
            #expect(source.credentialScope != same.credentialScope)
        }
        same = source
        same.kind = .openRouterOAuth
        #expect(source.credentialScope != same.credentialScope)
    }

    @Test("OpenRouter uses Chat Completions and rejects an altered OAuth destination")
    func routerEndpoint() throws {
        var configuration = ProviderConfiguration(kind: .openRouterOAuth, baseURL: ProviderKind.openRouterOAuth.defaultBaseURL, model: "openai/gpt-5-mini")
        let client = RemoteAIClient(configuration: configuration, apiKey: "fixture")
        #expect(try client.endpointURL().absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        let response = Data(#"{"choices":[{"message":{"content":"{\"allowed\":true}"}}]}"#.utf8)
        #expect(try client.extractText(from: response) == #"{"allowed":true}"#)
        configuration.baseURL = "https://elsewhere.example.com"
        #expect(throws: GenerationError.self) { try RemoteAIClient(configuration: configuration, apiKey: "fixture").endpointURL() }
    }
}
