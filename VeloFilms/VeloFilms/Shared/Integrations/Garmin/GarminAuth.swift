import Foundation

enum GarminError: LocalizedError {
    case notAuthenticated
    case downloadFailed(Int)
    case ssoFailed(String)
    case mfaRequired

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:     return "Not signed in to Garmin Connect"
        case .downloadFailed(let c): return "Garmin download failed (HTTP \(c))"
        case .ssoFailed(let msg):   return "Garmin sign-in failed: \(msg)"
        case .mfaRequired:          return "Multi-factor authentication is enabled on this account — please disable it temporarily to use Garmin Connect import"
        }
    }
}

/// Handles Garmin Connect authentication via the SSO form-based login.
/// Garmin has no public OAuth2 for consumer Connect — this mirrors what the
/// Python garminconnect library does: POST credentials to sso.garmin.com,
/// parse the service ticket from the HTML response, then exchange it at
/// connect.garmin.com to establish a cookie session.
@MainActor
final class GarminAuth {
    static let shared = GarminAuth()

    private(set) var isAuthenticated = false
    private(set) var displayName: String = ""

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        session = URLSession(configuration: config)
    }

    // MARK: - Sign in

    func signIn(email: String, password: String) async throws {
        let serviceURL = "https://connect.garmin.com/modern/"
        var comps = URLComponents(string: "https://sso.garmin.com/sso/signin")!
        comps.queryItems = [
            .init(name: "service",              value: serviceURL),
            .init(name: "clientId",             value: "GarminConnect"),
            .init(name: "gauthHost",            value: "https://sso.garmin.com/sso"),
            .init(name: "consumeServiceTicket", value: "false"),
        ]
        let signinURL = comps.url!

        // Step 1: GET signin page to obtain CSRF token
        var r1 = URLRequest(url: signinURL)
        r1.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        r1.setValue("text/html", forHTTPHeaderField: "Accept")
        let (d1, _) = try await session.data(for: r1)
        let html1 = String(data: d1, encoding: .utf8) ?? ""

        guard let csrf = extractCSRF(from: html1) else {
            throw GarminError.ssoFailed("Could not load Garmin login page — check network connection")
        }

        // Step 2: POST credentials
        var r2 = URLRequest(url: signinURL)
        r2.httpMethod = "POST"
        r2.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r2.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        r2.setValue(signinURL.absoluteString, forHTTPHeaderField: "Referer")
        r2.httpBody = formEncode([
            "username": email, "password": password,
            "_csrf": csrf, "embed": "false", "displayNameRequired": "false",
        ])
        let (d2, _) = try await session.data(for: r2)
        let html2 = String(data: d2, encoding: .utf8) ?? ""

        if html2.contains("mfa-code") || html2.contains("verificationCode") {
            throw GarminError.mfaRequired
        }
        if html2.contains("incorrectPasswordMessage") || html2.contains("Your credentials are incorrect") {
            throw GarminError.ssoFailed("Incorrect email or password")
        }

        // Step 3: Extract service ticket from HTML redirect
        guard let ticket = extractTicket(from: html2) else {
            throw GarminError.ssoFailed("Authentication failed — no session ticket in response")
        }

        // Step 4: Exchange ticket at connect.garmin.com to establish cookie session
        var r3 = URLRequest(url: URL(string: "https://connect.garmin.com/modern/?ticket=\(ticket)")!)
        r3.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        _ = try await session.data(for: r3)

        // Verify session is live
        try await verifySession()
        guard isAuthenticated else {
            throw GarminError.ssoFailed("Session could not be established after ticket exchange")
        }

        // Persist email for next launch prefill
        UserDefaults.standard.set(email, forKey: "garminEmail")
    }

    func signOut() {
        isAuthenticated = false; displayName = ""
        HTTPCookieStorage.shared.cookies?
            .filter { $0.domain.contains("garmin.com") }
            .forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        UserDefaults.standard.removeObject(forKey: "garminEmail")
    }

    var savedEmail: String? { UserDefaults.standard.string(forKey: "garminEmail") }

    // MARK: - Session verification

    func verifySession() async throws {
        let url = URL(string: "https://connect.garmin.com/modern/currentuser-service/user/info")!
        var req = baseRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            isAuthenticated = false
            return
        }
        displayName = (json["displayName"] as? String)
                   ?? (json["userName"] as? String)
                   ?? "Garmin User"
        isAuthenticated = true
    }

    // MARK: - Authenticated HTTP

    func getData(url: URL) async throws -> Data {
        let req = baseRequest(url: url)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw GarminError.downloadFailed(0)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GarminError.downloadFailed(http.statusCode)
        }
        return data
    }

    // MARK: - Private helpers

    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 VeloFilms"

    private func baseRequest(url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("https://connect.garmin.com", forHTTPHeaderField: "Origin")
        req.setValue("https://connect.garmin.com/modern/activities", forHTTPHeaderField: "Referer")
        req.setValue("NF", forHTTPHeaderField: "NK")
        return req
    }

    private func formEncode(_ params: [String: String]) -> Data? {
        params.map { k, v in
            let kEnc = k.addingPercentEncoding(withAllowedCharacters: .formAllowed) ?? k
            let vEnc = v.addingPercentEncoding(withAllowedCharacters: .formAllowed) ?? v
            return "\(kEnc)=\(vEnc)"
        }.joined(separator: "&").data(using: .utf8)
    }

    private func extractCSRF(from html: String) -> String? {
        for pattern in [#"name="_csrf"\s+value="([^"]+)""#, #"value="([^"]+)"\s+name="_csrf""#] {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(m.range(at: 1), in: html) else { continue }
            return String(html[range])
        }
        return nil
    }

    private func extractTicket(from html: String) -> String? {
        // Garmin SSO embeds the ticket in a JS redirect or service URL
        for pattern in [
            #"ticket=([A-Za-z0-9.\-_]+)"#,
            #"window\.location\.replace\("https://connect\.garmin\.com[^"]*ticket=([^"&]+)"#,
        ] {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(m.range(at: 1), in: html) else { continue }
            return String(html[range])
        }
        return nil
    }
}

private extension CharacterSet {
    static let formAllowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-._~"))
}
