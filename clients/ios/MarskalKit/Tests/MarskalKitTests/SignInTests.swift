import CryptoKit
import Foundation
import Testing
@testable import MarskalKit

struct ServerAddressTests {
    @Test(arguments: [
        ("marskal.example", "https://marskal.example"),
        ("  https://Marskal.Example/ ", "https://marskal.example"),
        ("http://marskal.localhost:8275", "http://marskal.localhost:8275"),
        ("https://marskal.example/tasks/", "https://marskal.example/tasks"),
    ])
    func addressesBecomeBaseURLs(typed: String, expected: String) {
        #expect(ServerAddress.parse(typed)?.absoluteString == expected)
    }

    @Test(arguments: ["", "ftp://marskal.example", "https://"])
    func otherAddressesAreRefused(typed: String) {
        #expect(ServerAddress.parse(typed) == nil)
    }
}

struct SignInTests {
    @Test func theAuthorizationURLCarriesAnS256Challenge() async throws {
        let stub = StubServer { _, _ in (200, metadata) }
        let signIn = try await SignIn.start(server: server, session: stub.session)

        #expect(stub.paths() == ["/.well-known/oauth-authorization-server"])
        let items = URLComponents(url: signIn.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })

        #expect(signIn.url.path() == "/oauth2/auth")
        #expect(query["client_id"] == "marskal-ios")
        #expect(query["redirect_uri"] == "app.marskal.ios:/oauth/callback")
        #expect(query["scope"] == "offline_access sync:read sync:write")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["code_challenge"] == Data(SHA256.hash(data: Data(signIn.verifier.utf8))).base64URL)
        #expect(query["state"] == signIn.state)
    }

    @Test func theCodeIsTradedWithTheVerifier() async throws {
        let stub = StubServer { request, _ in
            request.url?.path() == "/oauth2/token"
                ? (200, #"{"access_token": "a1", "refresh_token": "r1", "expires_in": 3600}"#)
                : (200, metadata)
        }
        let signIn = try await SignIn.start(server: server, session: stub.session)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let callback = URL(string: "app.marskal.ios:/oauth/callback?code=c1&state=\(signIn.state)")!

        let tokens = try await signIn.finish(callback: callback, session: stub.session, now: now)

        #expect(tokens == Tokens(access: "a1", refresh: "r1", expiresAt: now.addingTimeInterval(3600)))
        let sent = form(stub.requests.last!.body)
        #expect(sent["grant_type"] == "authorization_code")
        #expect(sent["code"] == "c1")
        #expect(sent["code_verifier"] == signIn.verifier)
        #expect(sent["redirect_uri"] == "app.marskal.ios:/oauth/callback")
    }

    @Test func aCallbackForAnotherSignInIsRefused() async throws {
        let stub = StubServer { _, _ in (200, metadata) }
        let signIn = try await SignIn.start(server: server, session: stub.session)
        let callback = URL(string: "app.marskal.ios:/oauth/callback?code=c1&state=other")!

        await #expect(throws: ServerError.oauth("invalid_state")) {
            try await signIn.finish(callback: callback, session: stub.session)
        }
    }

    @Test func aDeniedConsentIsAnOAuthError() async throws {
        let stub = StubServer { _, _ in (200, metadata) }
        let signIn = try await SignIn.start(server: server, session: stub.session)
        let callback = URL(string: "app.marskal.ios:/oauth/callback?error=access_denied&state=\(signIn.state)")!

        await #expect(throws: ServerError.oauth("access_denied")) {
            try await signIn.finish(callback: callback, session: stub.session)
        }
    }
}
