import Foundation

/// A single resampled GPX telemetry point (1Hz grid).
struct GPXPoint {
    var epoch: Double       // Unix timestamp (seconds)
    var lat: Double
    var lon: Double
    var elevation: Double   // metres
    var hr: Double?
    var cadence: Double?
    var speedKmh: Double    // computed from haversine + Δt
    var gradientPct: Double // ((ele2 - ele1) / dist_m) * 100
}

/// Parses a .gpx file using XMLParser and resamples to a 1Hz timeline.
/// Mirrors flatten.py: gpxpy parse → 1-second rows with speed + gradient.
final class GPXParser: NSObject, XMLParserDelegate {

    // MARK: - Public API

    /// Parse a GPX file and return 1Hz-resampled telemetry points.
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

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "trkpt" {
            currentLat = attributes["lat"].flatMap(Double.init)
            currentLon = attributes["lon"].flatMap(Double.init)
            currentEle = nil; currentTime = nil; currentHR = nil; currentCadence = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        switch currentElement {
        case "ele":          currentEle = Double(s)
        case "time":         currentTime = s
        case "gpxtpx:hr":    currentHR = Double(s)
        case "gpxtpx:cad":   currentCadence = Double(s)
        default: break
        }
    }

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
                hr: currentHR, cadence: currentCadence
            ))
        }
        currentElement = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }

    // MARK: - Resample to 1Hz

    private func resample(_ raw: [RawPoint]) -> [GPXPoint] {
        guard raw.count >= 2 else { return [] }
        let sorted = raw.sorted { $0.epoch < $1.epoch }
        let startEpoch = sorted.first!.epoch.rounded(.down)
        let endEpoch   = sorted.last!.epoch.rounded(.up)

        var out: [GPXPoint] = []
        var t = startEpoch
        while t <= endEpoch {
            // Interpolate between the two surrounding raw points
            guard let (before, after) = surrounding(t, in: sorted) else { t += 1; continue }
            let frac = after.epoch == before.epoch ? 0.0 : (t - before.epoch) / (after.epoch - before.epoch)
            let lat  = before.lat + (after.lat - before.lat) * frac
            let lon  = before.lon + (after.lon - before.lon) * frac
            let ele  = before.elevation + (after.elevation - before.elevation) * frac
            let hr   = interpolateOpt(before.hr, after.hr, frac: frac)
            let cad  = interpolateOpt(before.cadence, after.cadence, frac: frac)
            out.append(GPXPoint(epoch: t, lat: lat, lon: lon, elevation: ele,
                                hr: hr, cadence: cad, speedKmh: 0, gradientPct: 0))
            t += 1
        }

        // Second pass: compute speed and gradient from adjacent points
        for i in out.indices {
            if i == 0 { continue }
            let prev = out[i - 1]
            let curr = out[i]
            let dt = curr.epoch - prev.epoch
            guard dt > 0 else { continue }
            let dist = haversineM(prev.lat, prev.lon, curr.lat, curr.lon)
            out[i].speedKmh    = (dist / dt) * 3.6
            out[i].gradientPct = dist > 0 ? ((curr.elevation - prev.elevation) / dist) * 100 : 0
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
        var s = str
        // Cycliq UTC bug: cameras record local time tagged as 'Z'.
        // We reinterpret 'Z' using each camera's known timezone in ExtractStep;
        // here we just parse the timestamp at face value and let ExtractStep fix it.
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fmt.date(from: s) { return date.timeIntervalSince1970 }
        fmt.formatOptions = [.withInternetDateTime]
        if let date = fmt.date(from: s) { return date.timeIntervalSince1970 }
        return nil
    }
}

// MARK: - Haversine distance

func haversineM(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
    let R = 6_371_000.0
    let dLat = (lat2 - lat1) * .pi / 180
    let dLon = (lon2 - lon1) * .pi / 180
    let a = sin(dLat/2)*sin(dLat/2) + cos(lat1 * .pi/180)*cos(lat2 * .pi/180)*sin(dLon/2)*sin(dLon/2)
    return R * 2 * atan2(sqrt(a), sqrt(1 - a))
}

// MARK: - GPX index for O(log n) epoch lookup

struct GPXIndex {
    let points: [GPXPoint]

    /// Returns the point whose epoch is closest to `epoch`, or nil if |delta| > tolerance.
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
}
