import Foundation

/// Downloads activity data from Strava and converts it to the GPX/segments formats.
/// Mirrors strava_client.py: builds GPX from streams API, fetches segment efforts.
struct StravaClient {
    private let auth = StravaAuth.shared
    private let baseURL = "https://www.strava.com/api/v3"

    // MARK: - Activity list

    func recentActivities(page: Int = 1, perPage: Int = 30) async throws -> [[String: Any]] {
        let token = try requireToken()
        let url = URL(string: "\(baseURL)/athlete/activities?page=\(page)&per_page=\(perPage)")!
        return try await get(url: url, token: token)
    }

    // MARK: - GPX export (built from streams — more reliable than export endpoint)

    func downloadGPX(activityID: Int, to outputURL: URL) async throws {
        let token = try requireToken()

        // Fetch streams: latlng, altitude, time, heartrate, cadence
        let streamsURL = URL(string: "\(baseURL)/activities/\(activityID)/streams?keys=latlng,altitude,time,heartrate,cadence&key_by_type=true")!
        let streams: [String: Any] = try await get(url: streamsURL, token: token)

        let gpxString = buildGPX(from: streams)
        try gpxString.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Segment efforts

    func segmentEfforts(activityID: Int, to outputURL: URL) async throws {
        let token = try requireToken()
        let url = URL(string: "\(baseURL)/activities/\(activityID)?include_all_efforts=true")!
        let activity: [String: Any] = try await get(url: url, token: token)

        guard let efforts = activity["segment_efforts"] as? [[String: Any]] else { return }
        let segments: [[String: Any]] = efforts.compactMap { effort -> [String: Any]? in
            guard let seg = effort["segment"] as? [String: Any],
                  let name = seg["name"] as? String,
                  let startTime = effort["start_date"] as? String,
                  let elapsed = effort["elapsed_time"] as? Int else { return nil }
            let prRank = effort["pr_rank"] as? Int
            return [
                "name": name,
                "start_time": startTime,
                "elapsed_time": elapsed,
                "pr_rank": prRank as Any,
                "distance": seg["distance"] ?? 0,
                "average_grade": seg["average_grade"] ?? 0
            ]
        }

        let data = try JSONSerialization.data(withJSONObject: segments, options: .prettyPrinted)
        try data.write(to: outputURL, options: .atomic)
    }

    // MARK: - GPX construction from streams

    private func buildGPX(from streams: [String: Any]) -> String {
        let latlng    = (streams["latlng"]    as? [String: Any])?["data"]   as? [[Double]] ?? []
        let altitude  = (streams["altitude"]  as? [String: Any])?["data"]   as? [Double]   ?? []
        let time      = (streams["time"]      as? [String: Any])?["data"]   as? [Int]       ?? []
        let heartrate = (streams["heartrate"] as? [String: Any])?["data"]   as? [Int]       ?? []
        let cadence   = (streams["cadence"]   as? [String: Any])?["data"]   as? [Int]       ?? []

        var trkpts = ""
        let fmt = ISO8601DateFormatter()
        let epoch0 = Double(time.first ?? 0)

        for i in 0..<latlng.count {
            guard latlng[i].count == 2 else { continue }
            let lat  = latlng[i][0], lon = latlng[i][1]
            let ele  = i < altitude.count  ? altitude[i]  : 0.0
            let t    = i < time.count      ? time[i]      : 0
            let hr   = i < heartrate.count ? heartrate[i] : -1
            let cad  = i < cadence.count   ? cadence[i]   : -1

            let ts = fmt.string(from: Date(timeIntervalSince1970: epoch0 + Double(t)))
            var ext = ""
            if hr >= 0 || cad >= 0 {
                ext = "<extensions><gpxtpx:TrackPointExtension>"
                if hr  >= 0 { ext += "<gpxtpx:hr>\(hr)</gpxtpx:hr>" }
                if cad >= 0 { ext += "<gpxtpx:cad>\(cad)</gpxtpx:cad>" }
                ext += "</gpxtpx:TrackPointExtension></extensions>"
            }
            trkpts += "<trkpt lat=\"\(lat)\" lon=\"\(lon)\"><ele>\(ele)</ele><time>\(ts)</time>\(ext)</trkpt>\n"
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="VeloFilms"
             xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
        <trk><trkseg>
        \(trkpts)
        </trkseg></trk>
        </gpx>
        """
    }

    // MARK: - HTTP

    private func requireToken() throws -> String {
        guard let token = auth.accessToken else { throw StravaError.noToken }
        return token
    }

    private func get<T>(url: URL, token: String) async throws -> T {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data)
        guard let typed = json as? T else {
            throw URLError(.cannotParseResponse)
        }
        return typed
    }
}
