import Foundation

/// Downloads GPX from Garmin Connect.
/// Mirrors garmin_client.py but uses URLSession instead of the Python garminconnect library.
/// NOTE: Garmin Connect does not have a public API — this uses the same undocumented
///       endpoints as the Python library. Authentication may break with Garmin updates.
struct GarminClient {
    private let session = URLSession.shared
    private var authCookies: [HTTPCookie] = []

    // MARK: - Authentication (form-based, no OAuth)

    mutating func signIn(username: String, password: String) async throws {
        // Garmin uses a multi-step SSO flow. The Python library handles this via
        // multiple redirects. Full implementation requires replicating those steps.
        // TODO: Phase 3 — implement Garmin SSO with URLSession + cookie handling.
        throw GarminError.notImplemented
    }

    // MARK: - Activity list

    func activities(limit: Int = 20) async throws -> [[String: Any]] {
        let url = URL(string: "https://connect.garmin.com/activitylist-service/activities/search/activities?activityType=cycling&limit=\(limit)")!
        let (data, _) = try await authenticatedGet(url: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        return json ?? []
    }

    // MARK: - GPX download

    func downloadGPX(activityID: Int, to outputURL: URL) async throws {
        let url = URL(string: "https://connect.garmin.com/download-service/export/gpx/activity/\(activityID)")!
        let (data, response) = try await authenticatedGet(url: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw GarminError.downloadFailed
        }
        try data.write(to: outputURL, options: .atomic)
    }

    // MARK: - Private

    private func authenticatedGet(url: URL) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Mozilla/5.0 VeloFilms", forHTTPHeaderField: "User-Agent")
        for cookie in authCookies {
            req.addValue("\(cookie.name)=\(cookie.value)", forHTTPHeaderField: "Cookie")
        }
        return try await session.data(for: req)
    }
}

enum GarminError: LocalizedError {
    case notAuthenticated, downloadFailed, notImplemented
    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not signed in to Garmin Connect"
        case .downloadFailed:   return "Garmin GPX download failed"
        case .notImplemented:   return "Garmin Connect sign-in not yet implemented"
        }
    }
}
