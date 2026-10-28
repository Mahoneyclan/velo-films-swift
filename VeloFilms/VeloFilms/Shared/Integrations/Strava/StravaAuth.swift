// StravaAuth.swift
// Strava sign-in (OAuth 2) and token storage. Used by StravaClient and StravaImportView.

import Foundation
import AuthenticationServices
import os

// Compile-time constant URL; the force-unwrap cannot fail.
private let stravaTokenURL = URL(string: "https://www.strava.com/oauth/token")!

/// Signs the user in to Strava and keeps their access token valid.
///
/// Sign-in uses `ASWebAuthenticationSession`, so the user types their Strava password on strava.com, never in
/// the app. The returned authorisation code is exchanged for an access token (valid about 6 hours) and a refresh
/// token, both stored in the Keychain. Ported from `strava_client.py` in the original Python app (not in this repo).
///
/// Main-actor isolated: it presents UI and is used from views.
@MainActor
final class StravaAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    /// The single shared instance; token state is app-wide.
    static let shared = StravaAuth()

    // Captured on MainActor just before session.start() so presentationAnchor never
    // needs a scene-less UIWindow fallback (deprecated on iOS 26).
#if !os(macOS)
    private var authScene: UIWindowScene?
#endif

    private let clientID     = StravaSecrets.clientID
    private let clientSecret = StravaSecrets.clientSecret
    // Host must match the "Authorization Callback Domain" in Strava API settings (localhost)
    private let redirectURI  = "velofilms://localhost/strava"
    private let scope        = "activity:read_all"

    // Security: the tokens grant access to the user's Strava account, so they live in the Keychain,
    // not UserDefaults. The account names are permanent (earlier versions used them as UserDefaults keys).
    private static let accessTokenKey  = "stravaAccessToken"
    private static let refreshTokenKey = "stravaRefreshToken"

    private override init() {
        super.init()
        Self.migrateTokensFromUserDefaults()
    }

    /// Moves tokens saved by earlier versions from UserDefaults into the Keychain, then deletes the
    /// plain-text copy. The copy is only deleted once the Keychain write succeeds; if it fails, the user
    /// is shown as signed out and can sign in again.
    private static func migrateTokensFromUserDefaults() {
        let defaults = UserDefaults.standard
        for key in [accessTokenKey, refreshTokenKey] {
            guard let legacy = defaults.string(forKey: key) else { continue }
            if KeychainStore.string(for: key) != nil || KeychainStore.set(legacy, for: key) {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// The current access token, or `nil` when signed out. May be expired; use `ensureValidToken()` for API calls.
    private(set) var accessToken: String? {
        get { KeychainStore.string(for: Self.accessTokenKey) }
        set { KeychainStore.set(newValue, for: Self.accessTokenKey) }
    }
    /// The long-lived token used to obtain new access tokens without asking the user to sign in again.
    private(set) var refreshToken: String? {
        get { KeychainStore.string(for: Self.refreshTokenKey) }
        set { KeychainStore.set(newValue, for: Self.refreshTokenKey) }
    }
    // Not secret, so it stays in UserDefaults.
    private var tokenExpiry: Date? {
        get { UserDefaults.standard.object(forKey: "stravaTokenExpiry") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "stravaTokenExpiry") }
    }

    /// `true` when an access token is stored. It may still need refreshing.
    var isAuthenticated: Bool { accessToken != nil }

    /// Returns an access token that is valid for at least 5 more minutes, refreshing it first if needed.
    ///
    /// The 5-minute margin avoids a token expiring part-way through a multi-request download.
    /// - Returns: A bearer token for the Strava API.
    /// - Throws: `StravaError.noToken` when signed out; `.sessionExpired` if Strava no longer accepts the refresh
    ///   token (the stored tokens are then deleted); `.httpError`, `.unexpectedReply` or `URLError` otherwise.
    /// - Note: A refresh replaces both stored tokens.
    func ensureValidToken() async throws -> String {
        if let token = accessToken,
           let expiry = tokenExpiry,
           expiry > Date().addingTimeInterval(300) {
            return token
        }
        if let refresh = refreshToken {
            return try await refreshAccessToken(refresh)
        }
        throw StravaError.noToken
    }

    private func refreshAccessToken(_ refresh: String) async throws -> String {
        do {
            return try await requestTokens(["refresh_token": refresh, "grant_type": "refresh_token"])
        } catch StravaError.signInRejected {
            // The refresh token was revoked or has expired: forget it so the screen offers sign-in again.
            signOut()
            throw StravaError.sessionExpired
        }
    }

    /// Shows Strava's sign-in page and, once the user approves, stores the new tokens.
    ///
    /// Requests `activity:read_all` so private rides can be imported too.
    /// - Returns: The new access token.
    /// - Throws: `ASWebAuthenticationSessionError` if the user cancels; `StravaError.missingCallbackURL`,
    ///   `.missingCode` or `.stateMismatch` if Strava's reply is incomplete or not ours; `.signInRejected` or
    ///   `.unexpectedReply` from the token exchange; `URLError` on network failure or timeout.
    func authenticate() async throws -> String {
        // Security: a random one-time value sent with the request and checked in the reply, so a callback
        // that this sign-in didn't start (e.g. another app opening velofilms://) is rejected.
        let state = UUID().uuidString
        // Compile-time constant URL; the force-unwrap cannot fail.
        var components = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")!
        components.queryItems = [
            .init(name: "state",         value: state),
            .init(name: "client_id",     value: clientID),
            .init(name: "redirect_uri",  value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "approval_prompt", value: "auto"),
            .init(name: "scope",         value: scope),
        ]

#if !os(macOS)
        authScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
#endif

        let callbackURL = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: "velofilms"
            ) { url, error in
                if let error { cont.resume(throwing: error); return }
                guard let url else { cont.resume(throwing: StravaError.missingCallbackURL); return }
                cont.resume(returning: url)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        let replyItems = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard replyItems.first(where: { $0.name == "state" })?.value == state else { throw StravaError.stateMismatch }
        guard let code = replyItems.first(where: { $0.name == "code" })?.value else { throw StravaError.missingCode }

        return try await requestTokens(["code": code, "grant_type": "authorization_code"])
    }

    /// Deletes the stored tokens. Does not revoke the app's access on strava.com.
    func signOut() {
        accessToken = nil; refreshToken = nil; tokenExpiry = nil
    }

    // MARK: - Token exchange

    /// Posts to Strava's token endpoint (code exchange or refresh) and stores the returned tokens.
    ///
    /// Security: the HTTP status is checked before the reply is trusted, so an error reply (e.g. a wrong client
    /// secret) is reported as a rejected sign-in rather than an unreadable reply, and nothing is stored.
    private func requestTokens(_ grant: [String: String]) async throws -> String {
        var req = URLRequest(url: stravaTokenURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(
            grant.merging(["client_id": clientID, "client_secret": clientSecret]) { current, _ in current })
        let (data, response) = try await StravaNetwork.session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // Only 400/401 mean the code or refresh token itself was refused; others (e.g. 429 rate limit,
            // 408 timeout) are temporary and must not sign the user out.
            throw [400, 401].contains(status) ? StravaError.signInRejected(status) : StravaError.httpError(status)
        }
        guard let tokens = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw StravaError.unexpectedReply
        }
        accessToken  = tokens.accessToken
        refreshToken = tokens.refreshToken
        tokenExpiry  = Date(timeIntervalSince1970: Double(tokens.expiresAt))
        return tokens.accessToken
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding
#if os(macOS)
    /// The window the Strava sign-in sheet attaches to.
    /// - Parameter session: The sign-in session asking.
    /// - Returns: The app's key window, or a new one if there is none.
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSWindow()
    }
#else
    /// The window the Strava sign-in sheet attaches to.
    /// - Parameter session: The sign-in session asking.
    /// - Returns: The sign-in scene's first window, or a new one if there is none.
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // authScene is captured on MainActor in authenticate() before session.start(),
        // so this path always has a scene during active OAuth flows.
        let scene = authScene
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        if let window = scene?.windows.first { return window }
        if let scene { return UIWindow(windowScene: scene) }
        preconditionFailure("StravaAuth: no UIWindowScene — unreachable during active UI interaction")
    }
#endif

    private struct TokenResponse: Decodable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Int
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresAt = "expires_at"
        }
    }
}

/// Errors from Strava sign-in and API calls, worded for display.
enum StravaError: LocalizedError {
    /// The sign-in sheet closed without a reply.
    case missingCallbackURL
    /// Strava's reply had no authorisation code (e.g. the user declined access).
    case missingCode
    /// The reply's `state` didn't match this sign-in, so it was ignored.
    case stateMismatch
    /// No tokens are stored.
    case noToken
    /// Strava refused the code or refresh token (HTTP 4xx from the token endpoint).
    case signInRejected(Int)
    /// The refresh token stopped working; the user must sign in again.
    case sessionExpired
    /// A reply that isn't the JSON the app expects.
    case unexpectedReply
    /// Any other unsuccessful HTTP status.
    case httpError(Int)

    /// Plain-language message: what happened and what to do next.
    var errorDescription: String? {
        switch self {
        case .missingCallbackURL, .missingCode:
            return "Strava sign-in didn't finish. Please try again and tap Authorize."
        case .stateMismatch:
            return "The Strava sign-in reply couldn't be verified, so it was ignored. Please sign in again."
        case .noToken:
            return "You're not signed in to Strava. Sign in to see your rides."
        case .signInRejected(let code):
            return "Strava didn't accept the sign-in (code \(code)). Please sign in again."
        case .sessionExpired:
            return "Your Strava sign-in has expired. Please sign in again."
        case .unexpectedReply:
            return "Strava sent a reply the app couldn't read. Please try again later."
        case .httpError(401):
            return "Strava didn't accept your sign-in. Please sign out and sign in again."
        case .httpError(404):
            return "Strava couldn't find that activity. It may have been deleted or made private."
        case .httpError(429):
            return "Strava's download limit was reached. Wait 15 minutes and try again."
        case .httpError(let code) where code >= 500:
            return "Strava is having problems right now (code \(code)). Try again later."
        case .httpError(let code):
            return "Strava returned an error (code \(code)). Please try again."
        }
    }
}
