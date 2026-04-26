import Foundation

struct GarminActivity: Decodable, Identifiable {
    let activityId: Int
    let activityName: String
    let startTimeLocal: String       // "YYYY-MM-DD HH:MM:SS"
    let distance: Double?
    let duration: Double?
    let activityType: ActivityType?

    var id: Int { activityId }

    struct ActivityType: Decodable {
        let typeKey: String
    }

    private static let cyclingKeys: Set<String> = [
        "road_biking", "mountain_biking", "gravel_cycling", "cycling",
        "indoor_cycling", "virtual_ride", "e_bike_fitness", "e_bike_mountain",
    ]
    var isCycling: Bool { Self.cyclingKeys.contains(activityType?.typeKey ?? "") }
    var displayDate: String { String(startTimeLocal.prefix(10)) }

    var distanceKm: String {
        guard let d = distance else { return "—" }
        return String(format: "%.1f km", d / 1000)
    }
    var durationStr: String {
        guard let d = duration else { return "—" }
        let s = Int(d); let h = s / 3600; let m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
    var suggestedProjectName: String {
        let date = String(startTimeLocal.prefix(10))
        let safe = activityName
            .replacingOccurrences(of: "[^a-zA-Z0-9 ]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return "\(date) \(safe)"
    }
}

struct GarminClient {
    private let auth = GarminAuth.shared
    private let base = "https://connect.garmin.com"

    // MARK: - Activity list

    func recentActivities(limit: Int = 30) async throws -> [GarminActivity] {
        guard auth.isAuthenticated else { throw GarminError.notAuthenticated }
        let url = URL(string: "\(base)/activitylist-service/activities/search/activities?start=0&limit=\(limit)")!
        let data = try await auth.getData(url: url)
        let decoder = JSONDecoder()
        return try decoder.decode([GarminActivity].self, from: data)
    }

    // MARK: - GPX download

    func downloadGPX(activityID: Int, to outputURL: URL) async throws {
        guard auth.isAuthenticated else { throw GarminError.notAuthenticated }
        let url = URL(string: "\(base)/modern/proxy/download-service/export/gpx/activity/\(activityID)")!
        let data = try await auth.getData(url: url)
        guard data.count > 100 else { throw GarminError.downloadFailed(0) }
        try data.write(to: outputURL, options: .atomic)
    }
}
