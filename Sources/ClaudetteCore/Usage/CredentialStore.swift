import Foundation
#if canImport(Security)
import Security
#endif

public enum CredentialFailureReason: String, Error, Sendable, Equatable, CaseIterable {
    case noKeychainItem = "no_keychain_item"
    /// Keychain item exists but holds only `mcpOAuth` (Claude Code 2.1.x
    /// shape) with no `claudeAiOauth`. Needs re-auth, not a network retry.
    case mcpOnly = "mcp_only"
    /// Token minted with only `user:inference`; usage endpoint needs
    /// `user:profile`. Surface "run `claude login`".
    case scopeMissing = "scope_missing"
    case expired = "expired"
    case malformed = "malformed"

    public var guidance: String {
        switch self {
        case .noKeychainItem:
            return "No Claude Code credentials found. Sign in with `claude login`."
        case .mcpOnly:
            return "Claude Code stored MCP-only credentials. Re-authenticate with `claude login`."
        case .scopeMissing:
            return "This token can't read usage. Re-authenticate with `claude login`."
        case .expired:
            return "Claude Code token expired. Open Claude Code or run `claude login`."
        case .malformed:
            return "Stored credentials are unreadable. Re-authenticate with `claude login`."
        }
    }
}

public enum CredentialSource: String, Sendable, Equatable {
    case keychain
    case file
}

public struct Credentials: Sendable, Equatable {
    public let accessToken: String
    public let expiresAt: Date?
    public let scopes: [String]?
    public let subscriptionType: String?
    public let source: CredentialSource

    public init(
        accessToken: String,
        expiresAt: Date?,
        scopes: [String]?,
        subscriptionType: String?,
        source: CredentialSource
    ) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.scopes = scopes
        self.subscriptionType = subscriptionType
        self.source = source
    }
}

public protocol CredentialProviding: Sendable {
    func load() -> Result<Credentials, CredentialFailureReason>
}

/// Reads the token Claude Code already holds. No OAuth flow of our own.
///
/// 1. Keychain generic password, service `Claude Code-credentials`.
/// 2. File fallback `~/.claude/.credentials.json`, same JSON shape.
///
/// The keychain item is owned by Claude Code, so the first read triggers a
/// system permission prompt ("Always Allow" persists it — until the app's
/// signing identity changes).
public struct CredentialStore: CredentialProviding {
    public static let keychainService = "Claude Code-credentials"

    private let fileURL: URL

    public init(
        fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
    ) {
        self.fileURL = fileURL
    }

    public func load() -> Result<Credentials, CredentialFailureReason> {
        var keychainFailure: CredentialFailureReason?

        #if canImport(Security)
        switch Self.readKeychain() {
        case .success(let data):
            switch Self.parse(data, source: .keychain) {
            case .success(let creds):
                return Self.validate(creds)
            case .failure(let reason):
                keychainFailure = reason
            }
        case .failure(let reason):
            keychainFailure = reason
        }
        #endif

        if let data = try? Data(contentsOf: fileURL) {
            switch Self.parse(data, source: .file) {
            case .success(let creds):
                return Self.validate(creds)
            case .failure(let reason):
                // Prefer the more actionable keychain diagnosis when both fail.
                return .failure(keychainFailure == .mcpOnly ? .mcpOnly : reason)
            }
        }

        return .failure(keychainFailure ?? .noKeychainItem)
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

    /// Parses the credentials JSON: `{"claudeAiOauth": {"accessToken": ...}}`.
    public static func parse(_ data: Data, source: CredentialSource) -> Result<Credentials, CredentialFailureReason> {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.malformed)
        }
        guard let oauth = object["claudeAiOauth"] as? [String: Any] else {
            return .failure(object["mcpOAuth"] != nil ? .mcpOnly : .malformed)
        }
        guard let token = oauth["accessToken"] as? String, !token.isEmpty else {
            return .failure(.malformed)
        }
        // expiresAt is epoch milliseconds in Claude Code's store.
        let expiresAt = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000.0) }
        let scopes = oauth["scopes"] as? [String]
        let subscription = oauth["subscriptionType"] as? String
        return .success(Credentials(
            accessToken: token,
            expiresAt: expiresAt,
            scopes: scopes,
            subscriptionType: subscription,
            source: source))
    }

    #if canImport(Security)
    private static func readKeychain() -> Result<Data, CredentialFailureReason> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return .failure(.noKeychainItem)
        }
        return .success(data)
    }
    #endif
}
