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
        case .mfaRequired:           return "Multi-factor authentication is required — disable MFA on your Garmin account or use a Garmin MFA exemption app to proceed"
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

/// Replicates the garth Python library's SSO + OAuth1→OAuth2 flow exactly.
/// Flow:
///   1. GET sso/embed (set cookies)
///   2. GET sso/signin (get CSRF)
///   3. POST sso/signin (submit credentials, expect <title>Success</title>)
///   4. Parse ticket from `embed?ticket=…` in response HTML
///   5. GET connectapi/oauth-service/oauth/preauthorized (OAuth1 signed) → OAuth1 token
///   6. POST connectapi/oauth-service/oauth/exchange/user/2.0 (OAuth1 signed) → OAuth2 token
///   All subsequent API calls: Bearer {access_token} on connectapi.garmin.com
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

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        ssoSession = URLSession(configuration: cfg)
        loadPersistedTokens()
        if oauth2Token != nil { isAuthenticated = !(oauth2Token!.isExpired) }
    }

    // MARK: - Public

    var savedEmail: String? { UserDefaults.standard.string(forKey: "garminEmail") }

    func checkSession() async {
        guard let t = oauth2Token, !t.isExpired else {
            // Try refresh via OAuth1 if we have one
            if let o1 = oauth1Token, !(oauth2Token?.isExpired == false) {
                if let fresh = try? await exchangeOAuth2(oauth1: o1) {
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
        _ = t   // valid token already stored
        isAuthenticated = true
        if displayName.isEmpty { await fetchDisplayName() }
    }

    func signIn(email: String, password: String) async throws {
        try await loadConsumerCredentials()

        let ssoBase  = "https://sso.garmin.com"
        let ssoEmbed = "\(ssoBase)/sso/embed"

        let embedParams: [String: String] = [
            "id": "gauth-widget", "embedWidget": "true",
            "gauthHost": "\(ssoBase)/sso",
        ]
        let signinParams: [String: String] = [
            "id": "gauth-widget", "embedWidget": "true",
            "gauthHost": ssoEmbed, "service": ssoEmbed, "source": ssoEmbed,
            "redirectAfterAccountLoginUrl": ssoEmbed,
            "redirectAfterAccountCreationUrl": ssoEmbed,
        ]

        // Step 1: GET embed — establishes SSO session cookies
        _ = try await ssoGet(path: "\(ssoBase)/sso/embed", params: embedParams)

        // Step 2: GET signin — extract CSRF token
        let signinHTML = try await ssoGet(path: "\(ssoBase)/sso/signin", params: signinParams)
        guard let csrf = extractCSRF(from: signinHTML) else {
            throw GarminError.ssoFailed("Could not load Garmin login page — check network connection")
        }

        // Step 3: POST credentials
        let resultHTML = try await ssoPost(
            path: "\(ssoBase)/sso/signin", params: signinParams,
            body: ["username": email, "password": password, "embed": "true", "_csrf": csrf]
        )

        let title = extractTitle(from: resultHTML) ?? ""
        if title.contains("MFA") || title.contains("Factor") || resultHTML.contains("mfa-code") {
            throw GarminError.mfaRequired
        }
        guard title == "Success" else {
            throw GarminError.ssoFailed("Login failed (title: '\(title)') — check email and password")
        }

        // Step 4: Parse service ticket
        guard let ticket = extractTicket(from: resultHTML) else {
            throw GarminError.ssoFailed("No service ticket found in response")
        }

        // Step 5: OAuth1 preauth (uses connectapi.garmin.com with OAuth1 signing)
        let oauth1 = try await fetchOAuth1Token(ticket: ticket)
        oauth1Token = oauth1

        // Step 6: Exchange OAuth1 → OAuth2
        let oauth2 = try await exchangeOAuth2(oauth1: oauth1)
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
        let fresh = try await exchangeOAuth2(oauth1: o1)
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
        var comps = URLComponents(string: "https://connectapi.garmin.com/oauth-service/oauth/preauthorized")!
        comps.queryItems = [
            .init(name: "ticket",             value: ticket),
            .init(name: "login-url",          value: "https://sso.garmin.com/sso/embed"),
            .init(name: "accepts-mfa-tokens", value: "true"),
        ]
        let url = comps.url!
        var req = URLRequest(url: url)
        req.setValue(mobileUA, forHTTPHeaderField: "User-Agent")
        req.setValue(oauth1Header(method: "GET", url: url), forHTTPHeaderField: "Authorization")

        let (data, response) = try await apiSession.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw GarminError.ssoFailed("OAuth1 preauth HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        // Response is URL-encoded: oauth_token=...&oauth_token_secret=...
        let pairs = (String(data: data, encoding: .utf8) ?? "")
            .components(separatedBy: "&")
            .compactMap { pair -> (String, String)? in
                let kv = pair.components(separatedBy: "=")
                guard kv.count == 2 else { return nil }
                return (kv[0], kv[1].removingPercentEncoding ?? kv[1])
            }
        var dict = Dictionary(pairs, uniquingKeysWith: { $1 })
        guard let token = dict["oauth_token"], let secret = dict["oauth_token_secret"] else {
            throw GarminError.ssoFailed("OAuth1 response missing token fields: \(String(data: data, encoding: .utf8) ?? "")")
        }
        return GarminOAuth1Token(token: token, secret: secret, mfaToken: dict["mfa_token"])
    }

    // MARK: - OAuth2 exchange

    private func exchangeOAuth2(oauth1: GarminOAuth1Token) async throws -> GarminOAuth2Token {
        let url = URL(string: "https://connectapi.garmin.com/oauth-service/oauth/exchange/user/2.0")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(mobileUA, forHTTPHeaderField: "User-Agent")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(oauth1Header(method: "POST", url: url, tokenKey: oauth1.token, tokenSecret: oauth1.secret),
                     forHTTPHeaderField: "Authorization")
        if let mfa = oauth1.mfaToken { req.httpBody = "mfa_token=\(mfa)".data(using: .utf8) }

        let (data, response) = try await apiSession.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw GarminError.ssoFailed("OAuth2 exchange HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        let r = try JSONDecoder().decode(OAuth2TokenResponse.self, from: data)
        let now = Int(Date().timeIntervalSince1970)
        return GarminOAuth2Token(
            accessToken:          r.access_token,
            tokenType:            r.token_type,
            expiresAt:            now + r.expires_in,
            refreshToken:         r.refresh_token,
            refreshTokenExpiresAt: now + r.refresh_token_expires_in
        )
    }

    // MARK: - OAuth1 signing (RFC 3986 percent-encoding + HMAC-SHA1)

    private func oauth1Header(method: String, url: URL, tokenKey: String? = nil, tokenSecret: String? = nil) -> String {
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

        // Include URL query params in signature base string
        var allParams = params
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.forEach { allParams[$0.name] = $0.value ?? "" }

        let paramStr = allParams.sorted { $0.key < $1.key }
            .map { "\($0.key.o1enc)=\($0.value.o1enc)" }
            .joined(separator: "&")

        let baseURL = "\(url.scheme ?? "https")://\(url.host ?? "")\(url.path)"
        let baseStr = "\(method.uppercased())&\(baseURL.o1enc)&\(paramStr.o1enc)"
        let sigKey  = "\(consumerSecret.o1enc)&\((tokenSecret ?? "").o1enc)"

        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: Data(baseStr.utf8), using: SymmetricKey(data: Data(sigKey.utf8)))
        params["oauth_signature"] = Data(mac).base64EncodedString()

        return "OAuth " + params.sorted { $0.key < $1.key }
            .map { "\($0.key.o1enc)=\"\($0.value.o1enc)\"" }
            .joined(separator: ", ")
    }

    // MARK: - Consumer credentials (fetched from garth's S3 bucket — public)

    private func loadConsumerCredentials() async throws {
        guard consumerKey.isEmpty else { return }
        let url = URL(string: "https://thegarth.s3.amazonaws.com/oauth_consumer.json")!
        let (data, _) = try await apiSession.data(from: url)
        let creds = try JSONDecoder().decode(OAuthConsumerCredentials.self, from: data)
        consumerKey = creds.consumer_key
        consumerSecret = creds.consumer_secret
    }

    // MARK: - SSO HTTP helpers (use ssoSession with cookie jar)

    private func ssoGet(path: String, params: [String: String]) async throws -> String {
        var comps = URLComponents(string: path)!
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: comps.url!)
        req.setValue(browserUA, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await ssoSession.data(for: req)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func ssoPost(path: String, params: [String: String], body: [String: String]) async throws -> String {
        var comps = URLComponents(string: path)!
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(browserUA, forHTTPHeaderField: "User-Agent")
        req.httpBody = body.map { "\($0.key.formEnc)=\($0.value.formEnc)" }.joined(separator: "&").data(using: .utf8)
        let (data, _) = try await ssoSession.data(for: req)
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Display name

    private func fetchDisplayName() async {
        guard let token = try? await ensureValidToken() else { return }
        let url = URL(string: "https://connectapi.garmin.com/userprofile-service/socialProfile")!
        var req = URLRequest(url: url)
        req.setValue(mobileUA, forHTTPHeaderField: "User-Agent")
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

    // MARK: - HTML parsing

    private func extractCSRF(from html: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"name="_csrf"\s+value="(.+?)""#),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return String(html[r])
    }

    private func extractTitle(from html: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: "<title>(.+?)</title>"),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return String(html[r])
    }

    private func extractTicket(from html: String) -> String? {
        // garth looks for: embed?ticket=([^"]+)"
        guard let re = try? NSRegularExpression(pattern: #"embed\?ticket=([^"]+)""#),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return String(html[r])
    }

    private let browserUA  = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 VeloFilms"
    private let mobileUA   = "com.garmin.android.apps.connectmobile"
}

// MARK: - String helpers

private extension String {
    /// RFC 3986 unreserved-character encoding — required for OAuth1 signatures.
    var o1enc: String {
        addingPercentEncoding(withAllowedCharacters: .rfc3986Unreserved) ?? self
    }
    /// Standard form encoding for POST body fields.
    var formEnc: String {
        addingPercentEncoding(withAllowedCharacters: .formAllowed) ?? self
    }
}

private extension CharacterSet {
    static let rfc3986Unreserved = CharacterSet.alphanumerics.union(.init(charactersIn: "-._~"))
    static let formAllowed       = CharacterSet.alphanumerics.union(.init(charactersIn: "-._~"))
}
