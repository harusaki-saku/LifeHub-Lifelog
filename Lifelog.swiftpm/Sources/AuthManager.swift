import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

/// Cognito Hosted UI（auth.showlabo.com）に対するOAuth2 PKCE認証。
/// Sign in with AppleをCognitoのIdPとして連携すれば、ユーザー操作は生体認証1タップで完結する
/// （ideaLifelog.md §0参照。Sign in with Apple自体は無料、追加費用はApple Developer Programのみ）。
///
/// Config.swiftのcognitoClientId等をCognito側でアプリクライアントを作成してから差し替えて使うこと。
@MainActor
final class AuthManager: NSObject, ObservableObject {
    static let shared = AuthManager()

    /// idTokenの有効期限(1時間)に対し、この秒数を切ったら早めにrefreshする安全マージン。
    /// これが無いと、Background Delivery経由の同期がidToken失効直後に401で失敗し続ける
    /// （レビュー指摘・2026-07-05: refreshToken自動更新未実装だった）。
    private static let refreshMarginSeconds: TimeInterval = 60

    @Published private(set) var isSignedIn = false

    private var codeVerifier: String?

    func signIn() async throws {
        let verifier = Self.generateCodeVerifier()
        codeVerifier = verifier
        let challenge = Self.codeChallenge(for: verifier)

        var components = URLComponents()
        components.scheme = "https"
        components.host = Config.cognitoDomain
        components.path = "/oauth2/authorize"
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Config.cognitoClientId),
            URLQueryItem(name: "redirect_uri", value: Config.cognitoRedirectUri),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        guard let authURL = components.url,
              let callbackScheme = URL(string: Config.cognitoRedirectUri)?.scheme
        else {
            throw URLError(.badURL)
        }

        let code: String = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL,
                      let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "code" })?.value
                else {
                    continuation.resume(throwing: LifelogAPIError.invalidResponse)
                    return
                }
                continuation.resume(returning: code)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        try await exchangeCodeForTokens(code: code)
        isSignedIn = true
    }

    /// 有効なidTokenを返す。期限切れ間近・期限情報が無い場合はrefreshTokenで更新してから返す。
    /// refreshにも失敗した場合（refreshToken自体の失効等）はnilを返し、呼び出し側は
    /// 再ログイン（signIn）が必要と判断する。
    func currentIdToken() async throws -> String? {
        if let idToken = try KeychainHelper.readToken(key: Self.idTokenKey),
           let expiry = Self.readExpiryDate(),
           expiry > Date().addingTimeInterval(Self.refreshMarginSeconds) {
            return idToken
        }

        guard let refreshToken = try KeychainHelper.readToken(key: Self.refreshTokenKey) else {
            return nil
        }

        do {
            try await refreshTokens(refreshToken: refreshToken)
        } catch {
            return nil
        }

        return try KeychainHelper.readToken(key: Self.idTokenKey)
    }

    private func exchangeCodeForTokens(code: String) async throws {
        guard let verifier = codeVerifier else { throw URLError(.badURL) }

        var request = URLRequest(url: URL(string: "https://\(Config.cognitoDomain)/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "authorization_code",
            "client_id": Config.cognitoClientId,
            "code": code,
            "redirect_uri": Config.cognitoRedirectUri,
            "code_verifier": verifier,
        ]
        request.httpBody = body
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let tokens = try JSONDecoder().decode(CognitoTokenResponse.self, from: data)
        try saveTokens(tokens)
    }

    /// grant_type=refresh_token。Cognitoは通常このグラントで新しいrefresh_tokenを返さないため、
    /// 既存のrefreshTokenはKeychainに残したまま、idToken/accessToken/期限だけ更新する。
    private func refreshTokens(refreshToken: String) async throws {
        var request = URLRequest(url: URL(string: "https://\(Config.cognitoDomain)/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "refresh_token",
            "client_id": Config.cognitoClientId,
            "refresh_token": refreshToken,
        ]
        request.httpBody = body
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw LifelogAPIError.invalidResponse
        }

        let tokens = try JSONDecoder().decode(CognitoTokenResponse.self, from: data)
        try saveTokens(tokens)
    }

    private func saveTokens(_ tokens: CognitoTokenResponse) throws {
        try KeychainHelper.saveToken(tokens.idToken, key: Self.idTokenKey)
        if let refreshToken = tokens.refreshToken {
            try KeychainHelper.saveToken(refreshToken, key: Self.refreshTokenKey)
        }
        let expiry = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
        try KeychainHelper.saveToken(ISO8601DateFormatter().string(from: expiry), key: Self.idTokenExpiryKey)
    }

    private static func readExpiryDate() -> Date? {
        let raw = (try? KeychainHelper.readToken(key: idTokenExpiryKey)) ?? nil
        guard let raw else { return nil }
        return ISO8601DateFormatter().date(from: raw)
    }

    private static let idTokenKey = "lifelog.idToken"
    private static let refreshTokenKey = "lifelog.refreshToken"
    private static let idTokenExpiryKey = "lifelog.idTokenExpiry"

    private static func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension AuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }

        // フォールバックは通常到達しない想定（SwiftUI Appライフサイクルではsignin()呼び出し時点で
        // 必ずキーウィンドウが存在する）。念のため空のASPresentationAnchorで落ちないようにしている。
        return keyWindow ?? ASPresentationAnchor()
    }
}

private struct CognitoTokenResponse: Codable {
    let idToken: String
    let accessToken: String
    /// refresh_token grantのレスポンスには含まれないことが多いためoptional
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}
