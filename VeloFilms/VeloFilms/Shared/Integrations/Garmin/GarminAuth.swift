import Foundation
import CryptoKit

enum GarminError: LocalizedError {
    case notAuthenticated
    case downloadFailed(Int)
    case ssoFailed(String)
    case mfaRequired

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:      return "Not signed in to Garmin Connect"
        case .downloadFailed(let c): return "Garmin download failed (HTTP \(c))"
        case .ssoFailed(let msg):    return "Garmin sign-in failed: \(msg)"
        case .mfaRequired:           return "Multi-factor authentication is required — disable MFA on your Garmin account to proceed"
        }
    }
}

// MARK: - Token models

struct GarminOAuth1Token: Codable {
    let token: String
    let secret: String
    let mfaToken: String?
}

struct GarminOAuth2Token: Codable {
    let accessToken: String
    let tokenType: String
    let expiresAt: Int
    let refreshToken: String
    let refreshTokenExpiresAt: Int

    var isExpired: Bool { Int(Date().timeIntervalSince1970) >= expiresAt - 60 }
}

// MARK: - Decodable helpers

private struct OAuthConsumerCredentials: Decodable {
    let consumer_key: String
    let consumer_secret: String
}

private struct OAuth2TokenResponse: Decodable {
    let access_token: String
    let token_type: String
    let expires_in: Int
    let refresh_token: String
    let refresh_token_expires_in: Int
}

// MARK: - GarminAuth
//
// Replicates garth 0.5.3 SSO flow exactly:
//   1. GET sso/mobile/sso/en/sign-in  (set cookies)
//   2. POST sso/mobile/api/login      (JSON creds → serviceTicketId)
//   3. Best-effort GET sso/portal/sso/embed   (Cloudflare LB cookie)
//   4. GET connectapi/oauth-service/oauth/preauthorized  (OAuth1 signed, login-url=mobile.integration)
//   5. POST connectapi/oauth-service/oauth/exchange/user/2.0  (OAuth1 signed, audience=GARMIN_CONNECT_MOBILE_ANDROID_DI)
//   6. API calls: Authorization: Bearer {access_token}  User-Agent: GCM-iOS-5.22.1.4
@Observable
@MainActor
final class GarminAuth {
    static let shared = GarminAuth()

    private(set) var isAuthenticated = false
    private(set) var displayName: String = ""

    private(set) var oauth1Token: GarminOAuth1Token?
    private(set) var oauth2Token: GarminOAuth2Token?

    private var consumerKey: String = ""
    private var consumerSecret: String = ""

    private let ssoSession: URLSession    // preserves SSO cookies during login
    private let apiSession = URLSession.shared

    // garth 0.5.3 constants
    private let clientID   = "GCM_ANDROID_DARK"
    private let serviceURL = "https://mobile.integration.garmin.com/gcm/android"

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        ssoSession = URLSession(configuration: cfg)
        loadPersistedTokens()
        if let t = oauth2Token { isAuthenticated = !t.isExpired }
    }

    // MARK: - Public

    var savedEmail: String? { UserDefaults.standard.string(forKey: "garminEmail") }

    func checkSession() async {
        guard let t = oauth2Token, !t.isExpired else {
            if let o1 = oauth1Token, !(oauth2Token?.isExpired == false) {
                if let fresh = try? await exchangeOAuth2(oauth1: o1, forLogin: false) {
                    oauth2Token = fresh
                    persistTokens()
                    isAuthenticated = true
                    await fetchDisplayName()
                }
            } else {
                isAuthenticated = false
            }
            return
        }
        _ = t
        isAuthenticated = true
        if displayName.isEmpty { await fetchDisplayName() }
    }

    func signIn(email: String, password: String) async throws {
        try await loadConsumerCredentials()

        // Step 1: GET sign-in page — establishes SSO session cookies
        _ = try await ssoGet(
            "https://sso.garmin.com/mobile/sso/en/sign-in",
            params: ["clientId": clientID],
            extraHeaders: ["Sec-Fetch-Site": "none"]
        )

        // Step 2: POST credentials as JSON
        let loginParams: [String: String] = [
            "clientId": clientID,
            "locale":   "en-US",
            "service":  serviceURL,
        ]
        let loginBody: [String: Any] = [
            "username":     email,
            "password":     password,
            "rememberMe":   false,
            "captchaToken": "",
        ]
        let loginData = try await ssoPostJSON(
            "https://sso.garmin.com/mobile/api/login",
            params: loginParams,
            body: loginBody
        )
        guard let json = try? JSONSerialization.jsonObject(with: loginData) as? [String: Any] else {
            throw GarminError.ssoFailed("Invalid login response")
        }
        let status = (json["responseStatus"] as? [String: Any])?["type"] as? String ?? ""
        if status == "MFA_REQUIRED" { throw GarminError.mfaRequired }
        guard status == "SUCCESSFUL", let ticket = json["serviceTicketId"] as? String else {
            let msg = (json["responseStatus"] as? [String: Any])?["message"] as? String ?? status
            throw GarminError.ssoFailed("Login failed: \(msg.isEmpty ? "check email and password" : msg)")
        }

        // Step 3: Best-effort GET embed (sets Cloudflare LB cookie)
        _ = try? await ssoGet(
            "https://sso.garmin.com/portal/sso/embed",
            params: [:],
            extraHeaders: ["Sec-Fetch-Site": "same-origin"]
        )

        // Step 4: OAuth1 preauth
        let oauth1 = try await fetchOAuth1Token(ticket: ticket)
        oauth1Token = oauth1

        // Step 5: OAuth1→OAuth2 exchange (with audience)
        let oauth2 = try await exchangeOAuth2(oauth1: oauth1, forLogin: true)
        oauth2Token = oauth2
        isAuthenticated = true
        persistTokens()

        UserDefaults.standard.set(email, forKey: "garminEmail")
        await fetchDisplayName()
    }

    func ensureValidToken() async throws -> String {
        guard let token = oauth2Token else { throw GarminError.notAuthenticated }
        if !token.isExpired { return token.accessToken }
        guard let o1 = oauth1Token else { throw GarminError.notAuthenticated }
        let fresh = try await exchangeOAuth2(oauth1: o1, forLogin: false)
        oauth2Token = fresh
        persistTokens()
        return fresh.accessToken
    }

    func signOut() {
        isAuthenticated = false; displayName = ""
        oauth1Token = nil; oauth2Token = nil
        UserDefaults.standard.removeObject(forKey: "garminEmail")
        UserDefaults.standard.removeObject(forKey: "garminOAuth1Token")
        UserDefaults.standard.removeObject(forKey: "garminOAuth2Token")
    }

    // MARK: - OAuth1 preauth

    private func fetchOAuth1Token(ticket: String) async throws -> GarminOAuth1Token {
        // Build URL with serviceURL unencoded — garth does the same raw string interpolation.
        // Garmin's server exact-matches the login-url and redirects if it's percent-encoded.
        let rawURLStr = "https://connectapi.garmin.com/oauth-service/oauth/preauthorized"
            + "?ticket=\(ticket)&login-url=\(serviceURL)&accepts-mfa-tokens=true"
        guard let url = URL(string: rawURLStr) else {
            throw GarminError.ssoFailed("Could not construct preauth URL")
        }
        let queryParams = ["ticket": ticket, "login-url": serviceURL, "accepts-mfa-tokens": "true"]
        var req = URLRequest(url: url)
        req.setValue(oauthUA, forHTTPHeaderField: "User-Agent")
        req.setValue(oauth1Header(method: "GET", baseURL: url, extraQueryParams: queryParams),
                     forHTTPHeaderField: "Authorization")

        let (data, response) = try await apiSession.data(for: req, delegate: NoRedirectDelegate())
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) || (300..<400).contains(status) else {
            throw GarminError.ssoFailed("OAuth1 preauth HTTP \(status)")
        }
        let bodyStr = String(data: data, encoding: .utf8) ?? ""
        let pairs = bodyStr
            .components(separatedBy: "&")
            .compactMap { pair -> (String, String)? in
                let kv = pair.components(separatedBy: "=")
                guard kv.count == 2 else { return nil }
                return (kv[0], kv[1].removingPercentEncoding ?? kv[1])
            }
        let dict = Dictionary(pairs, uniquingKeysWith: { $1 })
        guard let token = dict["oauth_token"], let secret = dict["oauth_token_secret"] else {
            throw GarminError.ssoFailed("OAuth1 preauth missing token — body: \(bodyStr)")
        }
        return GarminOAuth1Token(token: token, secret: secret, mfaToken: dict["mfa_token"])
    }

    // MARK: - OAuth2 exchange

    private func exchangeOAuth2(oauth1: GarminOAuth1Token, forLogin: Bool) async throws -> GarminOAuth2Token {
        let url = URL(string: "https://connectapi.garmin.com/oauth-service/oauth/exchange/user/2.0")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(oauthUA, forHTTPHeaderField: "User-Agent")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(oauth1Header(method: "POST", baseURL: url, tokenKey: oauth1.token, tokenSecret: oauth1.secret),
                     forHTTPHeaderField: "Authorization")

        var bodyParts: [String] = []
        if forLogin { bodyParts.append("audience=GARMIN_CONNECT_MOBILE_ANDROID_DI") }
        if let mfa = oauth1.mfaToken { bodyParts.append("mfa_token=\(mfa)") }
        if !bodyParts.isEmpty { req.httpBody = bodyParts.joined(separator: "&").data(using: .utf8) }

        let (data, response) = try await apiSession.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw GarminError.ssoFailed("OAuth2 exchange HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        let r = try JSONDecoder().decode(OAuth2TokenResponse.self, from: data)
        let now = Int(Date().timeIntervalSince1970)
        return GarminOAuth2Token(
            accessToken:           r.access_token,
            tokenType:             r.token_type,
            expiresAt:             now + r.expires_in,
            refreshToken:          r.refresh_token,
            refreshTokenExpiresAt: now + r.refresh_token_expires_in
        )
    }

    // MARK: - OAuth1 signing (RFC 3986 + HMAC-SHA1)

    /// Signs a request. Pass `extraQueryParams` explicitly for URLs with raw (unencoded) query
    /// strings that URLComponents would decode incorrectly (e.g. the preauth login-url param).
    private func oauth1Header(
        method: String,
        baseURL url: URL,
        tokenKey: String? = nil,
        tokenSecret: String? = nil,
        extraQueryParams: [String: String] = [:]
    ) -> String {
        let ts    = String(Int(Date().timeIntervalSince1970))
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()

        var params: [String: String] = [
            "oauth_consumer_key":     consumerKey,
            "oauth_nonce":            nonce,
            "oauth_signature_method": "HMAC-SHA1",
            "oauth_timestamp":        ts,
            "oauth_version":          "1.0",
        ]
        if let tk = tokenKey { params["oauth_token"] = tk }

        var allParams = params
        if extraQueryParams.isEmpty {
            // Normal path: extract query params from URL
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.forEach { allParams[$0.name] = $0.value ?? "" }
        } else {
            // Explicit path: caller provides params (avoids URLComponents re-encoding issues)
            extraQueryParams.forEach { allParams[$0.key] = $0.value }
        }

        let paramStr = allParams.sorted { $0.key < $1.key }
            .map { "\($0.key.o1enc)=\($0.value.o1enc)" }
            .joined(separator: "&")

        let base = "\(url.scheme ?? "https")://\(url.host ?? "")\(url.path)"
        let baseStr = "\(method.uppercased())&\(base.o1enc)&\(paramStr.o1enc)"
        let sigKey  = "\(consumerSecret.o1enc)&\((tokenSecret ?? "").o1enc)"

        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: Data(baseStr.utf8), using: SymmetricKey(data: Data(sigKey.utf8)))
        params["oauth_signature"] = Data(mac).base64EncodedString()

        return "OAuth " + params.sorted { $0.key < $1.key }
            .map { "\($0.key.o1enc)=\"\($0.value.o1enc)\"" }
            .joined(separator: ", ")
    }

    // MARK: - Consumer credentials

    private func loadConsumerCredentials() async throws {
        guard consumerKey.isEmpty else { return }
        let url = URL(string: "https://thegarth.s3.amazonaws.com/oauth_consumer.json")!
        let (data, _) = try await apiSession.data(from: url)
        let creds = try JSONDecoder().decode(OAuthConsumerCredentials.self, from: data)
        consumerKey = creds.consumer_key
        consumerSecret = creds.consumer_secret
    }

    // MARK: - SSO HTTP helpers

    private func ssoGet(_ urlStr: String, params: [String: String], extraHeaders: [String: String] = [:]) async throws -> String {
        var comps = URLComponents(string: urlStr)!
        if !params.isEmpty { comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!)
        ssoPageHeaders.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        extraHeaders.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, _) = try await ssoSession.data(for: req)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func ssoPostJSON(_ urlStr: String, params: [String: String], body: [String: Any]) async throws -> Data {
        var comps = URLComponents(string: urlStr)!
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        ssoPageHeaders.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await ssoSession.data(for: req)
        return data
    }

    // MARK: - Display name

    private func fetchDisplayName() async {
        guard let token = try? await ensureValidToken() else { return }
        let url = URL(string: "https://connectapi.garmin.com/userprofile-service/socialProfile")!
        var req = URLRequest(url: url)
        req.setValue(apiUA, forHTTPHeaderField: "User-Agent")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let (data, _) = try? await apiSession.data(for: req),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            displayName = (json["displayName"] as? String) ?? (json["userName"] as? String) ?? "Garmin User"
        }
    }

    // MARK: - Persistence

    private func persistTokens() {
        if let d = try? JSONEncoder().encode(oauth2Token) { UserDefaults.standard.set(d, forKey: "garminOAuth2Token") }
        if let d = try? JSONEncoder().encode(oauth1Token) { UserDefaults.standard.set(d, forKey: "garminOAuth1Token") }
    }

    private func loadPersistedTokens() {
        if let d = UserDefaults.standard.data(forKey: "garminOAuth2Token") { oauth2Token = try? JSONDecoder().decode(GarminOAuth2Token.self, from: d) }
        if let d = UserDefaults.standard.data(forKey: "garminOAuth1Token") { oauth1Token = try? JSONDecoder().decode(GarminOAuth1Token.self, from: d) }
    }

    // MARK: - Constants

    // garth 0.5.3: GCM-iOS for API calls, connectmobile for OAuth signing, browser UA for SSO pages
    private let apiUA   = "GCM-iOS-5.22.1.4"
    private let oauthUA = "com.garmin.android.apps.connectmobile"
    private let ssoPageHeaders: [String: String] = [
        "User-Agent":      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
        "Accept":          "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9",
        "Sec-Fetch-Mode":  "navigate",
        "Sec-Fetch-Dest":  "document",
    ]
}

// MARK: - String helpers

private extension String {
    var o1enc: String {
        addingPercentEncoding(withAllowedCharacters: .rfc3986Unreserved) ?? self
    }
}

private extension CharacterSet {
    static let rfc3986Unreserved = CharacterSet.alphanumerics.union(.init(charactersIn: "-._~"))
}

// Prevents URLSession from following the OAuth preauth redirect to the service URL.
// The server redirects browsers to the service URL, but returns the token in the 302 body
// for properly signed OAuth requests. We read the body and stop there.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
