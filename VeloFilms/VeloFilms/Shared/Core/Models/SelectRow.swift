// SelectRow.swift
// Row model for select.jsonl, written by SelectStep and edited by the manual selection screen.

import Foundation

/// One row in select.jsonl — an EnrichRow plus selection metadata.
///
/// Internally stores a single `base: EnrichRow` rather than repeating every
/// enriched field. The JSONL format is unchanged: encoding and decoding are
/// flat (no nested "base" key) via a custom Codable implementation.
struct SelectRow: Codable {
    /// The enriched row this selection decision is about.
    var base: EnrichRow

    // Selection output — fields that exist only in the select step
    /// `true` if the clip will be used in the reel (manual choice if set, otherwise the automatic pick).
    var recommended: Bool
    /// `true` if this time falls in a Strava segment effort ranked as a personal record.
    var stravaPR: Bool
    /// `true` if only one camera has footage at this moment.
    var isSingleCamera: Bool
    /// `true` if the other camera also has footage at this moment (used for picture-in-picture).
    var paired: Bool
    /// Name of the Strava segment at this time, if any.
    var segmentName: String?
    /// Segment length in metres.
    var segmentDistance: Double?
    /// Segment average gradient in percent.
    var segmentGrade: Double?
    /// Set when the user manually overrides the AI recommendation on the Fine Tune screen (FineTuneModel).
    /// Non-nil means the user has explicitly chosen (true) or excluded (false) this clip.
    /// SelectStep preserves this value on re-run so manual decisions survive re-scoring.
    var manualOverride: Bool?

    /// Creates a row. Optional segment fields and `manualOverride` default to `nil`.
    /// - Parameters:
    ///   - base: The enriched row this selection is about.
    ///   - recommended: Whether the clip is picked for the reel.
    ///   - stravaPR: Whether the moment falls in a Strava PR effort.
    ///   - isSingleCamera: Whether only one camera filmed this moment.
    ///   - paired: Whether a partner row from the other camera was found.
    ///   - segmentName: Name of the Strava segment covering the moment.
    ///   - segmentDistance: That segment's length in metres.
    ///   - segmentGrade: That segment's average gradient in percent.
    ///   - manualOverride: The user's Fine Tune choice, or `nil` if untouched.
    init(base: EnrichRow,
         recommended: Bool,
         stravaPR: Bool,
         isSingleCamera: Bool,
         paired: Bool,
         segmentName: String? = nil,
         segmentDistance: Double? = nil,
         segmentGrade: Double? = nil,
         manualOverride: Bool? = nil) {
        self.base = base
        self.recommended = recommended
        self.stravaPR = stravaPR
        self.isSingleCamera = isSingleCamera
        self.paired = paired
        self.segmentName = segmentName
        self.segmentDistance = segmentDistance
        self.segmentGrade = segmentGrade
        self.manualOverride = manualOverride
    }

    // MARK: - Flat Codable — JSONL file format is identical to the old struct

    private enum CodingKeys: String, CodingKey {
        // EnrichRow fields (forwarded flat)
        case index, camera
        case clipNum          = "clip_num"
        case frameNumber      = "frame_number"
        case videoPath        = "video_path"
        case absTimeEpoch     = "abs_time_epoch"
        case absTimeIso       = "abs_time_iso"
        case sessionTsS       = "session_ts_s"
        case clipStartEpoch   = "clip_start_epoch"
        case adjustedStartTime = "adjusted_start_time"
        case durationS        = "duration_s"
        case source, fps
        case detectScore      = "detect_score"
        case numDetections    = "num_detections"
        case bboxArea         = "bbox_area"
        case detectedClasses  = "detected_classes"
        case objectDetected   = "object_detected"
        case sceneBoost       = "scene_boost"
        case gpxEpoch         = "gpx_epoch"
        case gpxTimeUtc       = "gpx_time_utc"
        case lat, lon, elevation
        case hrBpm            = "hr_bpm"
        case cadenceRpm       = "cadence_rpm"
        case speedKmh         = "speed_kmh"
        case gradientPct      = "gradient_pct"
        case scoreComposite   = "score_composite"
        case scoreWeighted    = "score_weighted"
        case segmentBoost     = "segment_boost"
        case momentId         = "moment_id"
        // Selection fields
        case recommended
        case stravaPR         = "strava_pr"
        case isSingleCamera   = "is_single_camera"
        case paired
        case segmentName      = "segment_name"
        case segmentDistance  = "segment_distance"
        case segmentGrade     = "segment_grade"
        case manualOverride   = "manual_override"
    }

    /// Decodes the flat JSON format. Telemetry and selection detail fields are optional; the rest are required.
    /// - Parameter decoder: Decoder positioned at one `select.jsonl` line.
    /// - Throws: `DecodingError` if a required field is missing or has the wrong type.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        base = EnrichRow(
            index:             try c.decode(String.self,  forKey: .index),
            camera:            try c.decode(String.self,  forKey: .camera),
            clipNum:           try c.decode(Int.self,     forKey: .clipNum),
            frameNumber:       try c.decode(Int.self,     forKey: .frameNumber),
            videoPath:         try c.decode(String.self,  forKey: .videoPath),
            absTimeEpoch:      try c.decode(Double.self,  forKey: .absTimeEpoch),
            absTimeIso:        try c.decode(String.self,  forKey: .absTimeIso),
            sessionTsS:        try c.decode(Double.self,  forKey: .sessionTsS),
            clipStartEpoch:    try c.decode(Double.self,  forKey: .clipStartEpoch),
            adjustedStartTime: try c.decode(String.self,  forKey: .adjustedStartTime),
            durationS:         try c.decode(Double.self,  forKey: .durationS),
            source:            try c.decode(String.self,  forKey: .source),
            fps:               try c.decode(Double.self,  forKey: .fps),
            detectScore:       try c.decode(Double.self,  forKey: .detectScore),
            numDetections:     try c.decode(Int.self,     forKey: .numDetections),
            bboxArea:          try c.decode(Double.self,  forKey: .bboxArea),
            detectedClasses:   try c.decode(String.self,  forKey: .detectedClasses),
            objectDetected:    try c.decode(Bool.self,    forKey: .objectDetected),
            sceneBoost:        try c.decode(Double.self,  forKey: .sceneBoost),
            gpxEpoch:          try c.decodeIfPresent(Double.self, forKey: .gpxEpoch),
            gpxTimeUtc:        try c.decodeIfPresent(String.self, forKey: .gpxTimeUtc),
            lat:               try c.decodeIfPresent(Double.self, forKey: .lat),
            lon:               try c.decodeIfPresent(Double.self, forKey: .lon),
            elevation:         try c.decodeIfPresent(Double.self, forKey: .elevation),
            hrBpm:             try c.decodeIfPresent(Double.self, forKey: .hrBpm),
            cadenceRpm:        try c.decodeIfPresent(Double.self, forKey: .cadenceRpm),
            speedKmh:          try c.decodeIfPresent(Double.self, forKey: .speedKmh),
            gradientPct:       try c.decodeIfPresent(Double.self, forKey: .gradientPct),
            scoreComposite:    try c.decode(Double.self,  forKey: .scoreComposite),
            scoreWeighted:     try c.decode(Double.self,  forKey: .scoreWeighted),
            segmentBoost:      try c.decode(Double.self,  forKey: .segmentBoost),
            momentId:          try c.decode(Int.self,     forKey: .momentId)
        )
        recommended    = try c.decode(Bool.self,   forKey: .recommended)
        stravaPR       = try c.decode(Bool.self,   forKey: .stravaPR)
        isSingleCamera = try c.decode(Bool.self,   forKey: .isSingleCamera)
        paired         = try c.decode(Bool.self,   forKey: .paired)
        segmentName     = try c.decodeIfPresent(String.self, forKey: .segmentName)
        segmentDistance = try c.decodeIfPresent(Double.self, forKey: .segmentDistance)
        segmentGrade    = try c.decodeIfPresent(Double.self, forKey: .segmentGrade)
        manualOverride  = try c.decodeIfPresent(Bool.self,   forKey: .manualOverride)
    }

    /// Encodes in the flat JSON format; `nil` optionals are omitted.
    /// - Parameter encoder: Encoder for one `select.jsonl` line.
    /// - Throws: Encoding errors from the encoder.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(base.index,             forKey: .index)
        try c.encode(base.camera,            forKey: .camera)
        try c.encode(base.clipNum,           forKey: .clipNum)
        try c.encode(base.frameNumber,       forKey: .frameNumber)
        try c.encode(base.videoPath,         forKey: .videoPath)
        try c.encode(base.absTimeEpoch,      forKey: .absTimeEpoch)
        try c.encode(base.absTimeIso,        forKey: .absTimeIso)
        try c.encode(base.sessionTsS,        forKey: .sessionTsS)
        try c.encode(base.clipStartEpoch,    forKey: .clipStartEpoch)
        try c.encode(base.adjustedStartTime, forKey: .adjustedStartTime)
        try c.encode(base.durationS,         forKey: .durationS)
        try c.encode(base.source,            forKey: .source)
        try c.encode(base.fps,               forKey: .fps)
        try c.encode(base.detectScore,       forKey: .detectScore)
        try c.encode(base.numDetections,     forKey: .numDetections)
        try c.encode(base.bboxArea,          forKey: .bboxArea)
        try c.encode(base.detectedClasses,   forKey: .detectedClasses)
        try c.encode(base.objectDetected,    forKey: .objectDetected)
        try c.encode(base.sceneBoost,        forKey: .sceneBoost)
        try c.encodeIfPresent(base.gpxEpoch,    forKey: .gpxEpoch)
        try c.encodeIfPresent(base.gpxTimeUtc,  forKey: .gpxTimeUtc)
        try c.encodeIfPresent(base.lat,         forKey: .lat)
        try c.encodeIfPresent(base.lon,         forKey: .lon)
        try c.encodeIfPresent(base.elevation,   forKey: .elevation)
        try c.encodeIfPresent(base.hrBpm,       forKey: .hrBpm)
        try c.encodeIfPresent(base.cadenceRpm,  forKey: .cadenceRpm)
        try c.encodeIfPresent(base.speedKmh,    forKey: .speedKmh)
        try c.encodeIfPresent(base.gradientPct, forKey: .gradientPct)
        try c.encode(base.scoreComposite,    forKey: .scoreComposite)
        try c.encode(base.scoreWeighted,     forKey: .scoreWeighted)
        try c.encode(base.segmentBoost,      forKey: .segmentBoost)
        try c.encode(base.momentId,          forKey: .momentId)
        try c.encode(recommended,            forKey: .recommended)
        try c.encode(stravaPR,               forKey: .stravaPR)
        try c.encode(isSingleCamera,         forKey: .isSingleCamera)
        try c.encode(paired,                 forKey: .paired)
        try c.encodeIfPresent(segmentName,     forKey: .segmentName)
        try c.encodeIfPresent(segmentDistance, forKey: .segmentDistance)
        try c.encodeIfPresent(segmentGrade,    forKey: .segmentGrade)
        try c.encodeIfPresent(manualOverride,  forKey: .manualOverride)
    }
}
