// GPXParser.swift
// GPX parsing, 1 Hz resampling with speed and gradient, distance maths, and fast nearest-time lookup.

import Foundation

/// A single resampled GPX telemetry point on the 1 Hz grid.
struct GPXPoint {
    /// Unix time in seconds (whole seconds after resampling).
    var epoch: Double
    /// Latitude in degrees.
    var lat: Double
    /// Longitude in degrees.
    var lon: Double
    /// Elevation in metres (0 where the GPX has none).
    var elevation: Double
    /// Heart rate in bpm, if recorded.
    var hr: Double?
    /// Cadence in rpm, if recorded.
    var cadence: Double?
    /// Speed in km/h, from the distance to the previous point (0 for the first point).
    var speedKmh: Double
    /// Gradient in percent: Strava's smoothed grade if available, otherwise measured over a 30-second window.
    var gradientPct: Double
    /// Strava's smoothed grade interpolated from `gpxtpx:grade`; `nil` for GPX files not built by StravaClient.
    var stravaGradePct: Double?
}

/// Parses a .gpx file using XMLParser and resamples to a 1Hz timeline.
/// Same output as `flatten.py` in the original Python app: 1-second rows with speed and gradient.
///
/// Not thread-safe; use the static `parse(url:gpxTimeOffsetS:)`, which creates a fresh parser each call.
final class GPXParser: NSObject, XMLParserDelegate {

    // MARK: - Public API

    /// Parses a GPX file and returns telemetry resampled to one point per second.
    ///
    /// Only `trkpt` elements with latitude, longitude and a parseable time are used. Values between recorded
    /// points are linearly interpolated.
    /// - Parameters:
    ///   - url: The `.gpx` file.
    ///   - gpxTimeOffsetS: Seconds added to every GPX time to line up with the camera clock.
    /// - Returns: Points in time order, or an empty array if fewer than two usable points were found.
    /// - Throws: File read errors or the XML parser's error.
    /// - Note: Memory and time grow with the ride's duration in seconds; a GPX with a corrupt far-off timestamp
    ///   produces a very long timeline.
    static func parse(url: URL, gpxTimeOffsetS: Double = AppConfig.gpxTimeOffsetS) throws -> [GPXPoint] {
        let parser = GPXParser(gpxTimeOffsetS: gpxTimeOffsetS)
        return try parser.parse(url: url)
    }

    // MARK: - Private

    private let gpxTimeOffsetS: Double
    private var rawPoints: [RawPoint] = []
    private var currentElement = ""
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentEle: Double?
    private var currentTime: String?
    private var currentHR: Double?
    private var currentCadence: Double?
    private var currentGrade: Double?
    private var parseError: Error?

    private init(gpxTimeOffsetS: Double) {
        self.gpxTimeOffsetS = gpxTimeOffsetS
    }

    private func parse(url: URL) throws -> [GPXPoint] {
        let data = try Data(contentsOf: url)
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self
        xmlParser.parse()
        if let error = parseError { throw error }
        return resample(rawPoints)
    }

    // MARK: - XMLParserDelegate

    /// Starts a new track point and reads its coordinates.
    /// - Parameters:
    ///   - parser: The XML parser.
    ///   - elementName: Element being opened; only `trkpt` starts a point.
    ///   - namespaceURI: Unused.
    ///   - qualifiedName: Unused.
    ///   - attributes: The element's attributes (`lat`, `lon` on `trkpt`).
    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "trkpt" {
            currentLat = attributes["lat"].flatMap(Double.init)
            currentLon = attributes["lon"].flatMap(Double.init)
            currentEle = nil; currentTime = nil; currentHR = nil; currentCadence = nil; currentGrade = nil
        }
    }

    /// Collects element text for the current track point.
    /// - Parameters:
    ///   - parser: The XML parser.
    ///   - string: A chunk of element text (may arrive in several pieces).
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        switch currentElement {
        case "ele":           currentEle = Double(s)
        case "time":          currentTime = s
        case "gpxtpx:hr":     currentHR = Double(s)
        case "gpxtpx:cad":    currentCadence = Double(s)
        case "gpxtpx:grade":  currentGrade = Double(s)
        default: break
        }
    }

    /// Stores the finished track point if it has coordinates and a valid time.
    /// - Parameters:
    ///   - parser: The XML parser.
    ///   - elementName: Element being closed.
    ///   - namespaceURI: Unused.
    ///   - qualifiedName: Unused.
    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "trkpt",
           let lat = currentLat, let lon = currentLon,
           let timeStr = currentTime,
           let epoch = iso8601Epoch(timeStr) {
            rawPoints.append(RawPoint(
                epoch: epoch + gpxTimeOffsetS,
                lat: lat, lon: lon,
                elevation: currentEle ?? 0,
                hr: currentHR, cadence: currentCadence, grade: currentGrade
            ))
        }
        currentElement = ""
    }

    /// Records the first XML error so `parse` can throw it.
    /// - Parameters:
    ///   - parser: The XML parser.
    ///   - parseError: The error XMLParser reported.
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }

    // MARK: - Resample to 1Hz

    private func resample(_ raw: [RawPoint]) -> [GPXPoint] {
        guard raw.count >= 2 else { return [] }
        let sorted = Self.removingStationaryElevationChanges(raw.sorted { $0.epoch < $1.epoch })
        let startEpoch = sorted[0].epoch.rounded(.down)
        let endEpoch   = sorted[sorted.count - 1].epoch.rounded(.up)

        var out: [GPXPoint] = []
        var t = startEpoch
        while t <= endEpoch {
            // Interpolate between the two surrounding raw points
            guard let (before, after) = surrounding(t, in: sorted) else { t += 1; continue }
            let frac = after.epoch == before.epoch ? 0.0 : (t - before.epoch) / (after.epoch - before.epoch)
            let lat  = before.lat + (after.lat - before.lat) * frac
            let lon  = before.lon + (after.lon - before.lon) * frac
            let ele  = before.elevation + (after.elevation - before.elevation) * frac
            let hr    = interpolateOpt(before.hr, after.hr, frac: frac)
            let cad   = interpolateOpt(before.cadence, after.cadence, frac: frac)
            let grade = interpolateOpt(before.grade, after.grade, frac: frac)
            out.append(GPXPoint(epoch: t, lat: lat, lon: lon, elevation: ele,
                                hr: hr, cadence: cad, speedKmh: 0, gradientPct: 0,
                                stravaGradePct: grade))
            t += 1
        }

        // Second pass: speed from adjacent 1-second points
        for i in out.indices {
            if i == 0 { continue }
            let prev = out[i - 1]
            let curr = out[i]
            let dt = curr.epoch - prev.epoch
            guard dt > 0 else { continue }
            let dist = haversineM(prev.lat, prev.lon, curr.lat, curr.lon)
            out[i].speedKmh = (dist / dt) * 3.6
        }

        // Third pass: gradient.
        // Prefer Strava's grade_smooth (already smoothed, DEM-corrected elevation) when present.
        // Fall back to a ±15 s centered window for non-Strava GPX files (Garmin export, manual drop).
        let hw = 15
        for i in out.indices {
            if let g = out[i].stravaGradePct {
                out[i].gradientPct = g
            } else {
                let lo = max(0, i - hw)
                let hi = min(out.count - 1, i + hw)
                let dist = haversineM(out[lo].lat, out[lo].lon, out[hi].lat, out[hi].lon)
                out[i].gradientPct = dist > 5 ? ((out[hi].elevation - out[lo].elevation) / dist) * 100 : 0
            }
        }
        return out
    }

    /// Below this average speed between two recorded points the rider counts as stationary (same 1 km/h
    /// threshold ScoreCalculator uses for "moving").
    private static let stationarySpeedKmh = 1.0

    /// Removes elevation changes recorded while the rider wasn't moving, keeping the profile continuous.
    ///
    /// Owner rule: elevation can't change while stationary, so any change between two points with almost no
    /// movement is bad data. A common cause is a barometric altimeter recalibrating during a long stop (seen as a
    /// 91 m drop over a 12-minute stop with 6 m of movement). Each such change is subtracted from every later
    /// point, so heights before the stop are kept and the shape of every hill after it is unchanged. Steep but
    /// moving sections are never altered or smoothed.
    /// - Parameter points: Recorded points in time order.
    /// - Returns: The same points with stationary elevation changes removed.
    private static func removingStationaryElevationChanges(_ points: [RawPoint]) -> [RawPoint] {
        guard points.count >= 2 else { return points }
        var out = points
        var offset = 0.0
        for i in 1..<points.count {
            let prev = points[i - 1], curr = points[i]
            let dt = curr.epoch - prev.epoch
            let moved = haversineM(prev.lat, prev.lon, curr.lat, curr.lon)
            let stationary = dt > 0 && (moved / dt) * 3.6 < stationarySpeedKmh
            if stationary { offset -= curr.elevation - prev.elevation }
            out[i].elevation = curr.elevation + offset
        }
        return out
    }

    private func surrounding(_ t: Double, in sorted: [RawPoint]) -> (RawPoint, RawPoint)? {
        // Binary search for insertion point
        var lo = 0, hi = sorted.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid].epoch < t { lo = mid + 1 } else { hi = mid }
        }
        guard lo > 0 else { return (sorted[0], sorted[min(1, sorted.count - 1)]) }
        guard lo < sorted.count else { return (sorted[sorted.count - 2], sorted[sorted.count - 1]) }
        return (sorted[lo - 1], sorted[lo])
    }

    private func interpolateOpt(_ a: Double?, _ b: Double?, frac: Double) -> Double? {
        guard let a, let b else { return a ?? b }
        return a + (b - a) * frac
    }

    // MARK: - Helpers

    private func iso8601Epoch(_ str: String) -> Double? {
        let s = str
        // GPX times are parsed at face value. Camera clock corrections (the Cycliq local-time-tagged-as-UTC
        // issue) are applied to the video side in ExtractStep, not here.
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fmt.date(from: s) { return date.timeIntervalSince1970 }
        fmt.formatOptions = [.withInternetDateTime]
        if let date = fmt.date(from: s) { return date.timeIntervalSince1970 }
        return nil
    }
}

// MARK: - Haversine distance

/// Great-circle distance between two coordinates, in metres (haversine formula, Earth radius 6,371 km).
/// - Parameters:
///   - lat1: First latitude in degrees.
///   - lon1: First longitude in degrees.
///   - lat2: Second latitude in degrees.
///   - lon2: Second longitude in degrees.
/// - Returns: Distance in metres.
func haversineM(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
    let R = 6_371_000.0
    let dLat = (lat2 - lat1) * .pi / 180
    let dLon = (lon2 - lon1) * .pi / 180
    let a = sin(dLat/2)*sin(dLat/2) + cos(lat1 * .pi/180)*cos(lat2 * .pi/180)*sin(dLon/2)*sin(dLon/2)
    return R * 2 * atan2(sqrt(a), sqrt(1 - a))
}

// MARK: - GPX index for O(log n) epoch lookup

/// Time-sorted GPX points with binary-search lookup by time.
struct GPXIndex {
    /// The points, which must be sorted by `epoch`.
    let points: [GPXPoint]

    /// Returns the point whose time is closest to `epoch`.
    /// - Parameters:
    ///   - epoch: Unix time in seconds.
    ///   - tolerance: Largest allowed time difference in seconds.
    /// - Returns: The nearest point, or `nil` if none is within `tolerance`.
    func nearest(epoch: Double, tolerance: Double = AppConfig.gpxTolerance) -> GPXPoint? {
        guard !points.isEmpty else { return nil }
        var lo = 0, hi = points.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if points[mid].epoch < epoch { lo = mid + 1 } else { hi = mid }
        }
        // Check lo and lo-1
        var best: GPXPoint? = nil
        var bestDiff = Double.infinity
        for idx in [lo - 1, lo, lo + 1] {
            guard (0..<points.count).contains(idx) else { continue }
            let diff = abs(points[idx].epoch - epoch)
            if diff < bestDiff { bestDiff = diff; best = points[idx] }
        }
        guard let best, bestDiff <= tolerance else { return nil }
        return best
    }
}

// MARK: - Private helpers

private struct RawPoint {
    var epoch: Double
    var lat: Double
    var lon: Double
    var elevation: Double
    var hr: Double?
    var cadence: Double?
    var grade: Double?  // gpxtpx:grade from Strava grade_smooth stream; nil for non-Strava GPX
}
