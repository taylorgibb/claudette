import Foundation

public enum CredentialFailureReason: String, Error, Sendable, Equatable, CaseIterable {
    case signedOut = "signed_out"
    case scopeMissing = "scope_missing"
    case expired = "expired"
}

public struct Credentials: Sendable, Equatable {
    public let accessToken: String
    public let expiresAt: Date?
    public let scopes: [String]?

    public init(accessToken: String, expiresAt: Date?, scopes: [String]?) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.scopes = scopes
    }
}

public protocol CredentialProviding: Sendable {
    func load() async -> Result<Credentials, CredentialFailureReason>
}

public struct CredentialStore: CredentialProviding {
    private let oauthTokens: OAuthTokenStore
    private let transport: any HTTPTransport

    public init(
        oauthTokens: OAuthTokenStore = OAuthTokenStore(),
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.oauthTokens = oauthTokens
        self.transport = transport
    }

    public func load() async -> Result<Credentials, CredentialFailureReason> {
        guard let stored = oauthTokens.load() else {
            return .failure(.signedOut)
        }
        var tokens = stored
        let expiringSoon = tokens.expiresAt
            .map { $0.timeIntervalSinceNow < ClaudeOAuth.refreshLeeway } ?? false
        if expiringSoon, let refreshToken = tokens.refreshToken {
            do {
                tokens = try await ClaudeOAuth.refresh(refreshToken, transport: transport)
                oauthTokens.save(tokens)
            } catch OAuthError.http(let status) where (400..<500).contains(status) {
                oauthTokens.clear()
                return .failure(.expired)
            } catch {
            }
        }
        return Self.validate(Credentials(
            accessToken: tokens.accessToken,
            expiresAt: tokens.expiresAt,
            scopes: tokens.scopes))
    }

    public static func validate(_ creds: Credentials) -> Result<Credentials, CredentialFailureReason> {
        if let scopes = creds.scopes, !scopes.isEmpty, !scopes.contains("user:profile") {
            return .failure(.scopeMissing)
        }
        if let expiresAt = creds.expiresAt, expiresAt < Date() {
            return .failure(.expired)
        }
        return .success(creds)
    }
}
