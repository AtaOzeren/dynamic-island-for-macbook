import CryptoKit
import Foundation
import KerNotchCore

/// The tokens that let KerNotch authenticate an RPC connection without asking
/// the user again.
public struct DiscordCredentials: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date

    public init(accessToken: String, refreshToken: String?, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// Whether the token is too close to expiry to spend a round trip on.
    func isExpiring(at now: Date) -> Bool {
        expiresAt.timeIntervalSince(now) < Self.refreshMargin
    }

    /// An hour of slack, so a token read just before it lapses is refreshed
    /// first rather than rejected mid-handshake.
    private static let refreshMargin: TimeInterval = 60 * 60
}

/// A PKCE verifier and the challenge derived from it, per RFC 7636.
///
/// PKCE is what lets a desktop app finish Discord's OAuth2 flow without a client
/// secret: the authorization code is only redeemable by whoever holds the
/// verifier, and the verifier never leaves this process until the exchange.
struct DiscordPKCE: Sendable {
    private static let verifierAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    private static let verifierLength = 64

    let verifier: String

    init(verifier: String) {
        self.verifier = verifier
    }

    static func generate() -> Self {
        var generator = SystemRandomNumberGenerator()
        let characters = (0..<verifierLength).map { _ in
            verifierAlphabet[Int.random(in: verifierAlphabet.indices, using: &generator)]
        }
        return Self(verifier: String(characters))
    }

    /// `BASE64URL(SHA256(verifier))` without padding, for the `S256` method.
    var challenge: String {
        Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// The two token requests the integration makes to Discord's OAuth2 endpoint.
public protocol DiscordTokenExchanging: Sendable {
    func redeem(code: String, verifier: String, clientID: DiscordClientID) async throws -> DiscordCredentials
    func refresh(_ refreshToken: String, clientID: DiscordClientID) async throws -> DiscordCredentials
}

public enum DiscordTokenExchangeError: Error, Equatable, Sendable {
    /// Discord answered, and said no: the code or refresh token is spent, or the
    /// application is not a public client.
    case rejected(status: Int, reason: String?)
    case malformedResponse
}

/// The production token client: form-encoded POSTs to
/// `https://discord.com/api/oauth2/token`.
///
/// The only outbound connection the integration makes, and only when the user
/// connects or a stored token needs renewing — never while a call is in
/// progress.
public struct URLSessionDiscordTokenExchange: DiscordTokenExchanging {
    private static let endpoint: URL = {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "discord.com"
        components.path = "/api/oauth2/token"
        guard let url = components.url else {
            preconditionFailure("A literal HTTPS URL always has a representation")
        }
        return url
    }()
    private static let requestTimeout: TimeInterval = 30

    private let session: URLSession
    private let now: @Sendable () -> Date

    public init(session: URLSession = .shared, now: @escaping @Sendable () -> Date = Date.init) {
        self.session = session
        self.now = now
    }

    public func redeem(code: String, verifier: String, clientID: DiscordClientID) async throws -> DiscordCredentials {
        try await requestToken([
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "client_id": clientID.rawValue,
        ])
    }

    public func refresh(_ refreshToken: String, clientID: DiscordClientID) async throws -> DiscordCredentials {
        try await requestToken([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID.rawValue,
        ])
    }

    private func requestToken(_ fields: [String: String]) async throws -> DiscordCredentials {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(DiscordFormEncoding.encode(fields).utf8)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = try? JSONDecoder().decode(DiscordTokenResponse.self, from: data)

        guard status == 200 else {
            throw DiscordTokenExchangeError.rejected(status: status, reason: body?.error)
        }
        guard let accessToken = body?.accessToken, let expiresIn = body?.expiresIn else {
            throw DiscordTokenExchangeError.malformedResponse
        }
        return DiscordCredentials(
            accessToken: accessToken,
            refreshToken: body?.refreshToken,
            expiresAt: now().addingTimeInterval(expiresIn)
        )
    }
}

enum DiscordFormEncoding {
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// Sorted by key so the same fields always produce the same body.
    static func encode(_ fields: [String: String]) -> String {
        fields
            .sorted { $0.key < $1.key }
            .map { "\(escape($0.key))=\(escape($0.value))" }
            .joined(separator: "&")
    }

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}

private struct DiscordTokenResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: TimeInterval?
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case error
    }
}
