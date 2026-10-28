// StravaClient.swift
// Strava API calls: list recent activities, build a GPX from activity streams, and save segments, laps and
// description into the project folder. Used by StravaImportView.

import Foundation

/// One activity from Strava's `GET /athlete/activities` list.
struct StravaActivity: Decodable, Identifiable {
    /// Strava activity ID.
    let id: Int
    /// Title the athlete gave the activity.
    let name: String
    /// Strava sport type, e.g. `"Ride"` or `"GravelRide"`.
    let type: String
    /// Local start time as Strava sends it (ISO 8601, e.g. `"2026-05-24T07:12:03Z"`; the `Z` is not true UTC).
    let startDateLocal: String
    /// Distance in metres.
    let distance: Double
    /// Moving time in seconds.
    let movingTime: Int

    /// Strava's JSON key names.
    enum CodingKeys: String, CodingKey {
        case id, name, type
        case startDateLocal = "start_date_local"
        case distance
        case movingTime = "moving_time"
    }

    /// `true` for the cycling sport types the import list shows.
    var isCycling: Bool {
        ["Ride", "VirtualRide", "GravelRide", "MountainBikeRide", "EBikeRide"].contains(type)
    }
    /// Date part of the local start time, `YYYY-MM-DD`.
    var displayDate: String { String(startDateLocal.prefix(10)) }
    /// Distance formatted for display, e.g. `"42.3 km"`.
    var distanceKm: String { String(format: "%.1f km", distance / 1000) }
    /// Moving time formatted for display, e.g. `"2h 5m"` or `"48m"`.
    var durationStr: String {
        let h = movingTime / 3600, m = (movingTime % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
    /// Default project name: date plus the activity name with anything except letters, digits and spaces
    /// removed, so it is safe as a folder name.
    var suggestedProjectName: String {
        let date = displayDate
        let safe = name
            .replacingOccurrences(of: "[^a-zA-Z0-9 ]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return "\(date) \(safe)"
    }
}

/// Calls the Strava REST API with the signed-in user's token from `StravaAuth`.
///
/// Main-actor isolated (project default); network awaits don't block the UI.
struct StravaClient {
    private static let isoFmt = ISO8601DateFormatter()
    private let auth = StravaAuth.shared
    private let baseURL = "https://www.strava.com/api/v3"

    // MARK: - Activity list

    /// Fetches one page of the athlete's activities, newest first. Includes non-cycling activities.
    /// - Parameters:
    ///   - page: 1-based page number.
    ///   - perPage: Activities per page (Strava allows up to 200).
    /// - Returns: The decoded activities.
    /// - Throws: `StravaError` when signed out or on an HTTP error; decoding errors for unexpected replies.
    func recentActivities(page: Int = 1, perPage: Int = 30) async throws -> [StravaActivity] {
        let token = try await auth.ensureValidToken()
        guard let url = URL(string: "\(baseURL)/athlete/activities?page=\(page)&per_page=\(perPage)") else { throw URLError(.badURL) }
        let data = try await getData(url: url, token: token)
        return try JSONDecoder().decode([StravaActivity].self, from: data)
    }

    // MARK: - GPX export (built from streams — more reliable than export endpoint)

    /// Downloads the activity's streams and writes them as a GPX 1.1 file.
    ///
    /// Built from the streams API because that proved more reliable than Strava's export endpoint. Heart rate, cadence and Strava's smoothed gradient go into Garmin TrackPointExtension tags
    /// (a standard GPX extension), which GPXParser reads back.
    /// - Parameters:
    ///   - activityID: Strava activity ID.
    ///   - startDate: Activity start; stream times are offsets from it.
    ///   - activityName: Written into the GPX metadata.
    ///   - outputURL: Where to write the file (overwritten).
    /// - Throws: `StravaError` on auth or HTTP failure; file write errors.
    func downloadGPX(activityID: Int, startDate: Date, activityName: String, to outputURL: URL) async throws {
        let token = try await auth.ensureValidToken()
        guard let streamsURL = URL(string: "\(baseURL)/activities/\(activityID)/streams?keys=latlng,altitude,time,heartrate,cadence,grade_smooth&key_by_type=true") else { throw URLError(.badURL) }
        let streamsData = try await getData(url: streamsURL, token: token)
        let streams = (try? JSONSerialization.jsonObject(with: streamsData) as? [String: Any]) ?? [:]
        let gpxString = buildGPX(from: streams, startDate: startDate, activityName: activityName)
        try gpxString.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Segment efforts + laps (single request)

    /// Fetches the activity's detail record and saves its description, segment efforts and laps.
    ///
    /// Each file is written only if Strava returns that section; if the reply isn't JSON, nothing is written.
    /// - Parameters:
    ///   - activityID: Strava activity ID.
    ///   - segmentsTo: Destination for `segments.json` (name, start time, elapsed time, PR rank, distance, grade).
    ///   - lapsTo: Destination for `laps.json`.
    ///   - descriptionTo: Destination for `description.txt`.
    /// - Throws: `StravaError` on auth or HTTP failure; errors writing segments or laps (description write
    ///   failures are ignored).
    func downloadActivityDetails(activityID: Int, segmentsTo: URL, lapsTo: URL,
                                 descriptionTo: URL) async throws {
        let token = try await auth.ensureValidToken()
        guard let url = URL(string: "\(baseURL)/activities/\(activityID)?include_all_efforts=true") else { throw URLError(.badURL) }
        let data = try await getData(url: url, token: token)
        guard let activity = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Activity description → description.txt (optional, present only when set on Strava)
        if let desc = activity["description"] as? String, !desc.isEmpty {
            try? desc.write(to: descriptionTo, atomically: true, encoding: .utf8)
        }

        // Segment efforts → segments.json
        if let efforts = activity["segment_efforts"] as? [[String: Any]] {
            let segments: [[String: Any]] = efforts.compactMap { effort -> [String: Any]? in
                guard let seg = effort["segment"] as? [String: Any],
                      let name = seg["name"] as? String,
                      let startTime = effort["start_date"] as? String,
                      let elapsed = effort["elapsed_time"] as? Int else { return nil }
                return [
                    "name": name, "start_time": startTime, "elapsed_time": elapsed,
                    "pr_rank": effort["pr_rank"] as Any,
                    "distance": seg["distance"] ?? 0, "average_grade": seg["average_grade"] ?? 0,
                ]
            }
            let segOut = try JSONSerialization.data(withJSONObject: segments, options: .prettyPrinted)
            try segOut.write(to: segmentsTo, options: .atomic)
        }

        // Laps → laps.json
        if let laps = activity["laps"] as? [[String: Any]] {
            let lapItems: [[String: Any]] = laps.compactMap { lap -> [String: Any]? in
                guard let startDate = lap["start_date"] as? String,
                      let elapsed = lap["elapsed_time"] as? Int else { return nil }
                return [
                    "name":       lap["name"] as? String ?? "Lap",
                    "start_date": startDate,
                    "elapsed_time": elapsed,
                    "distance":   lap["distance"] ?? 0,
                    "lap_index":  lap["lap_index"] ?? 0,
                ]
            }
            let lapsOut = try JSONSerialization.data(withJSONObject: lapItems, options: .prettyPrinted)
            try lapsOut.write(to: lapsTo, options: .atomic)
        }
    }

    // MARK: - GPX construction from streams

    private func buildGPX(from streams: [String: Any], startDate: Date, activityName: String) -> String {
        let latlng       = (streams["latlng"]       as? [String: Any])?["data"] as? [[Double]] ?? []
        let altitude     = (streams["altitude"]     as? [String: Any])?["data"] as? [Double]   ?? []
        let time         = (streams["time"]         as? [String: Any])?["data"] as? [Int]       ?? []
        let heartrate    = (streams["heartrate"]    as? [String: Any])?["data"] as? [Int]       ?? []
        let cadence      = (streams["cadence"]      as? [String: Any])?["data"] as? [Int]       ?? []
        // grade_smooth is Strava's own smoothed gradient (%) using corrected elevation.
        // May be absent on older activities or activities without elevation correction.
        let gradeSmooth  = (streams["grade_smooth"] as? [String: Any])?["data"] as? [Double]

        var trkpts = ""

        for i in 0..<latlng.count {
            guard latlng[i].count == 2 else { continue }
            let lat = latlng[i][0], lon = latlng[i][1]
            let ele = i < altitude.count  ? altitude[i]  : 0.0
            let t   = i < time.count      ? time[i]      : 0
            let hr  = i < heartrate.count ? heartrate[i] : -1
            let cad = i < cadence.count   ? cadence[i]   : -1

            let ts = Self.isoFmt.string(from: startDate.addingTimeInterval(Double(t)))
            var ext = ""
            let hasExt = hr >= 0 || cad >= 0 || (gradeSmooth != nil && i < (gradeSmooth?.count ?? 0))
            if hasExt {
                ext = "<extensions><gpxtpx:TrackPointExtension>"
                if hr  >= 0 { ext += "<gpxtpx:hr>\(hr)</gpxtpx:hr>" }
                if cad >= 0 { ext += "<gpxtpx:cad>\(cad)</gpxtpx:cad>" }
                if let g = gradeSmooth, i < g.count {
                    ext += "<gpxtpx:grade>\(g[i])</gpxtpx:grade>"
                }
                ext += "</gpxtpx:TrackPointExtension></extensions>"
            }
            trkpts += "<trkpt lat=\"\(lat)\" lon=\"\(lon)\"><ele>\(ele)</ele><time>\(ts)</time>\(ext)</trkpt>\n"
        }

        // Security: the name is the athlete's own text from Strava; escape it so characters like `<` or `&`
        // can't break the file or inject extra XML.
        let safeName = Self.xmlEscaped(activityName)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="VeloFilms"
             xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
        <metadata><name>\(safeName)</name></metadata>
        <trk><name>\(safeName)</name><trkseg>
        \(trkpts)
        </trkseg></trk>
        </gpx>
        """
    }

    /// Escapes the five XML special characters so `text` is safe as element content or an attribute value.
    /// - Parameter text: Untrusted text.
    /// - Returns: The escaped text.
    static func xmlEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    // MARK: - HTTP

    private func getData(url: URL, token: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await StravaNetwork.session.data(for: req, delegate: AuthPreservingDelegate(token: token))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw StravaError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }
}

/// The URL session for every Strava request.
///
/// Security: explicit timeouts, so a stalled connection fails with a clear error instead of leaving the import
/// screen spinning forever. 30 s is the longest wait for the next byte; 300 s caps a whole request, which covers
/// the largest stream download on a slow connection.
enum StravaNetwork {
    /// Shared session with the timeouts above.
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 30
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()
}

/// Re-adds the Authorization header after a redirect (URLSession strips it), but only when the
/// redirect target is https on strava.com or a subdomain.
///
/// Security: the bearer token grants access to the user's Strava account, so it must never be
/// forwarded to another host or over plain http. Any other redirect continues without it.
private final class AuthPreservingDelegate: NSObject, URLSessionTaskDelegate {
    let token: String
    init(token: String) { self.token = token }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var newReq = request
        if let url = request.url, url.scheme == "https",
           let host = url.host(percentEncoded: false)?.lowercased(),
           host == "strava.com" || host.hasSuffix(".strava.com") {
            newReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            newReq.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(newReq)
    }
}
