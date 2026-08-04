import Foundation
import CryptoKit

public struct OAuthTokens: Sendable, Equatable, Codable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?
    public let scopes: [String]?

    public init(accessToken: String, refreshToken: String?, expiresAt: Date?, scopes: [String]?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scopes = scopes
    }
}

public struct OAuthTokenStore: Sendable {
    private let url: URL

    public static func defaultURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Claudette/oauth-tokens.json")
    }

    public init(url: URL = Self.defaultURL()) {
        self.url = url
    }

    public var isSignedIn: Bool { load() != nil }

    public func load() -> OAuthTokens? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    public func save(_ tokens: OAuthTokens) {
        let fm = FileManager.default
        try? fm.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        try? data.write(to: url, options: [.atomic])
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

public enum OAuthError: Error, Equatable {
    case http(Int)
    case malformed
    case stateMismatch
}

public enum ClaudeOAuth {
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let callbackPort: UInt16 = 54545
    public static let redirectURI = "http://localhost:54545/callback"
    public static let scope = "org:create_api_key user:profile user:inference"

    public static let refreshLeeway: TimeInterval = 300

    public struct PKCE: Sendable {
        public let verifier: String
        public let challenge: String
        public let state: String

        public static func generate() -> PKCE {
            let verifier = base64URL(randomBytes(32))
            return PKCE(
                verifier: verifier,
                challenge: base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))),
                state: base64URL(randomBytes(32)))
        }
    }

    public static func authorizeURL(_ pkce: PKCE) -> URL {
        var components = URLComponents(
            url: Endpoints.oauthAuthorize, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.state),
        ]
        return components.url!
    }

    public static func signIn(
        store: OAuthTokenStore,
        transport: any HTTPTransport,
        openBrowser: @MainActor @Sendable @escaping (URL) -> Void
    ) async throws {
        let pkce = PKCE.generate()
        let server = try OAuthCallbackServer(port: callbackPort)
        defer { server.stop() }
        await openBrowser(authorizeURL(pkce))
        let callback = try await server.waitForCallback()
        guard callback.state == nil || callback.state == pkce.state else {
            throw OAuthError.stateMismatch
        }
        let tokens = try await exchange(
            code: callback.code, state: callback.state, pkce: pkce, transport: transport)
        store.save(tokens)
    }

    public static func exchange(
        code: String, state: String?, pkce: PKCE, transport: any HTTPTransport
    ) async throws -> OAuthTokens {
        var body: [String: Any] = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "code_verifier": pkce.verifier,
        ]
        if let state { body["state"] = state }
        return try await requestTokens(body, transport: transport)
    }

    public static func refresh(
        _ refreshToken: String, transport: any HTTPTransport
    ) async throws -> OAuthTokens {
        try await requestTokens([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ], transport: transport)
    }

    private static func requestTokens(
        _ body: [String: Any], transport: any HTTPTransport
    ) async throws -> OAuthTokens {
        let reply = try await transport.post(
            Endpoints.oauthToken,
            headers: ["Content-Type": "application/json"],
            body: try JSONSerialization.data(withJSONObject: body))
        guard reply.status == 200 else { throw OAuthError.http(reply.status) }
        return try parseTokens(reply.data)
    }

    static func parseTokens(_ data: Data, now: Date = Date()) throws -> OAuthTokens {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let accessToken = object["access_token"] as? String, !accessToken.isEmpty
        else { throw OAuthError.malformed }
        let expiresAt = (object["expires_in"] as? Double).map { now.addingTimeInterval($0) }
        let scopes = (object["scope"] as? String).map {
            $0.split(separator: " ").map(String.init)
        }
        return OAuthTokens(
            accessToken: accessToken,
            refreshToken: object["refresh_token"] as? String,
            expiresAt: expiresAt,
            scopes: scopes)
    }

    private static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: .min ... .max)
        }
        return Data(bytes)
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
