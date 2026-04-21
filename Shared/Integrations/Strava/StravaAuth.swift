import Foundation
import AuthenticationServices

/// Handles Strava OAuth2 flow via ASWebAuthenticationSession.
/// Mirrors strava_client.py OAuth handling.
@MainActor
final class StravaAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = StravaAuth()

    // Replace with your Strava app credentials from developers.strava.com
    private let clientID     = "YOUR_STRAVA_CLIENT_ID"
    private let clientSecret = "YOUR_STRAVA_CLIENT_SECRET"
    private let redirectURI  = "velofilms://oauth/strava"
    private let scope        = "activity:read_all"

    private(set) var accessToken: String? {
        get { UserDefaults.standard.string(forKey: "stravaAccessToken") }
        set { UserDefaults.standard.set(newValue, forKey: "stravaAccessToken") }
    }
    private(set) var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: "stravaRefreshToken") }
        set { UserDefaults.standard.set(newValue, forKey: "stravaRefreshToken") }
    }
    private var tokenExpiry: Date? {
        get { UserDefaults.standard.object(forKey: "stravaTokenExpiry") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "stravaTokenExpiry") }
    }

    var isAuthenticated: Bool { accessToken != nil }

    /// Launch the OAuth web flow. Returns the access token on success.
    func authenticate() async throws -> String {
        var components = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")!
        components.queryItems = [
            .init(name: "client_id",     value: clientID),
            .init(name: "redirect_uri",  value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "approval_prompt", value: "auto"),
            .init(name: "scope",         value: scope),
        ]

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

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else { throw StravaError.missingCode }

        return try await exchangeCode(code)
    }

    func signOut() {
        accessToken = nil; refreshToken = nil; tokenExpiry = nil
    }

    // MARK: - Token exchange

    private func exchangeCode(_ code: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode([
            "client_id": clientID, "client_secret": clientSecret,
            "code": code, "grant_type": "authorization_code"
        ])
        let (data, _) = try await URLSession.shared.data(for: req)
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken  = response.accessToken
        refreshToken = response.refreshToken
        tokenExpiry  = Date(timeIntervalSince1970: Double(response.expiresAt))
        return response.accessToken
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding
#if os(macOS)
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSWindow()
    }
#else
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first ?? UIWindow()
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

enum StravaError: LocalizedError {
    case missingCallbackURL, missingCode, noToken
    var errorDescription: String? {
        switch self {
        case .missingCallbackURL: return "Strava OAuth returned no callback URL"
        case .missingCode:        return "Strava OAuth callback missing code parameter"
        case .noToken:            return "Not authenticated with Strava"
        }
    }
}
