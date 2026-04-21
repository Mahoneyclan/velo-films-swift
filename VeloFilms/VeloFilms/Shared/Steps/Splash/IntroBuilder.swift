import Foundation

/// Builds _intro.mp4.
/// Mirrors splash.py IntroBuilder:
///   logo → map+banner(ride stats) → flip animation (1.2s) → collage → intro.mp3
///
/// Phase 4 implementation placeholder. Full AVVideoComposition implementation TBD.
enum IntroBuilder {
    static func build(project: Project,
                      selectRows: [SelectRow],
                      flattenRows: [FlattenRow],
                      bridge: any FFmpegBridge) async throws {
        let outputURL = project.clipsDir.appending(path: "_intro.mp4")
        guard !FileManager.default.fileExists(atPath: outputURL.path) else { return }

        // Stats for banner
        _ = computeRideStats(flattenRows: flattenRows)

        // 1. Gather recommended frame JPGs
        // 2. Build splash map at MAP_SPLASH_SIZE (2560×1440), centred on full route
        // 3. Render banner (ride name, distance, duration, speed, ascent)
        // 4. Compile flip animation frames
        // 5. Assemble via FFmpeg concat + audio

        // TODO: Phase 4 full implementation
        // For now, produce a placeholder 5-second black card
        _ = try await bridge.execute(arguments: [
            "-f", "lavfi", "-i", "color=c=black:s=1920x1080:d=5",
            "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo:d=5",
            "-c:v", "libx264", "-c:a", "aac", "-shortest",
            "-y", outputURL.path
        ])
    }

    static func computeRideStats(flattenRows: [FlattenRow]) -> RideStats {
        guard flattenRows.count >= 2 else { return RideStats() }
        var totalDist = 0.0
        var totalClimb = 0.0
        for i in 1..<flattenRows.count {
            let prev = flattenRows[i-1], curr = flattenRows[i]
            totalDist += haversineM(prev.lat, prev.lon, curr.lat, curr.lon)
            if curr.elevation > prev.elevation {
                totalClimb += curr.elevation - prev.elevation
            }
        }
        let durationS = (flattenRows.last?.gpxEpoch ?? 0) - (flattenRows.first?.gpxEpoch ?? 0)
        let avgSpeed = durationS > 0 ? (totalDist / 1000) / (durationS / 3600) : 0
        return RideStats(distanceKm: totalDist / 1000, durationS: durationS,
                         avgSpeedKmh: avgSpeed, totalClimbM: totalClimb)
    }
}

struct RideStats {
    var distanceKm: Double = 0
    var durationS: Double  = 0
    var avgSpeedKmh: Double = 0
    var totalClimbM: Double = 0
}
