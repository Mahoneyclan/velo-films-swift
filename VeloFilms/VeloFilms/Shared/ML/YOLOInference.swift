import Foundation
import CoreML
import CoreGraphics
import CoreVideo

/// Detection result for a single frame.
struct YOLODetection {
    var className: String
    var classIndex: Int
    var confidence: Float
    var boundingBox: CGRect   // normalised [0,1] coordinates
}

/// Core ML YOLO inference engine.
/// Uses MLModel directly (no Vision) to decode the raw [1, 84, 8400] output tensor
/// from the nms=False export. Applies per-class NMS in Swift.
final class YOLODetector {
    private var mlModel: MLModel?
    private let modelURL: URL
    private var outputName: String?

    /// Class weights for detectScore — reads from GlobalSettings so user can tune per-class.
    /// Disabled classes are omitted from the dict and filtered out at inference time.
    private static var classWeights: [Int: Float] {
        let s = GlobalSettings.shared
        var w = [Int: Float]()
        if s.yoloEnablePerson       { w[0]  = Float(s.yoloWeightPerson) }
        if s.yoloEnableBicycle      { w[1]  = Float(s.yoloWeightBicycle) }
        if s.yoloEnableCar          { w[2]  = Float(s.yoloWeightCar) }
        if s.yoloEnableMotorcycle   { w[3]  = Float(s.yoloWeightMotorcycle) }
        if s.yoloEnableBus          { w[5]  = Float(s.yoloWeightBus) }
        if s.yoloEnableTruck        { w[7]  = Float(s.yoloWeightTruck) }
        if s.yoloEnableTrafficLight { w[9]  = Float(s.yoloWeightTrafficLight) }
        if s.yoloEnableStopSign     { w[11] = Float(s.yoloWeightStopSign) }
        return w
    }

    /// bboxArea score — only cyclist/pedestrian classes that are currently enabled.
    private static var bboxAreaClasses: Set<Int> {
        var c = Set<Int>()
        if GlobalSettings.shared.yoloEnablePerson  { c.insert(0) }
        if GlobalSettings.shared.yoloEnableBicycle { c.insert(1) }
        return c
    }

    /// Classes that use the vehicle/sign confidence threshold instead of the global floor.
    private static let vehicleClasses: Set<Int> = [2, 3, 5, 7, 9, 11]

    private static let classNames: [Int: String] = [
        0: "person", 1: "bicycle", 2: "car", 3: "motorcycle",
        5: "bus", 7: "truck", 9: "traffic light", 11: "stop sign",
    ]

    init(modelURL: URL) {
        self.modelURL = modelURL
    }

    private func loadModel() throws -> MLModel {
        if let m = mlModel { return m }
        let model = try MLModel(contentsOf: modelURL)
        outputName = model.modelDescription.outputDescriptionsByName.keys.first
        mlModel = model
        return model
    }

    /// Run inference on a single frame. Returns detections and the scalar detect_score.
    func detect(image: CGImage) throws -> (detections: [YOLODetection], detectScore: Double, bboxArea: Double) {
        let model = try loadModel()
        guard let outName = outputName else { return ([], 0, 0) }

        let sz = AppConfig.yoloImageSize
        guard let pb = Self.pixelBuffer(from: image, width: sz, height: sz) else {
            return ([], 0, 0)
        }
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "image": MLFeatureValue(pixelBuffer: pb)
        ])
        let output = try model.prediction(from: input)

        guard let raw = output.featureValue(for: outName)?.multiArrayValue else {
            return ([], 0, 0)
        }

        let detections = decodeYOLO(raw)

        // detect_score = max(confidence × class_weight) across all boxes
        let detectScore = detections.map { det -> Double in
            let w = Self.classWeights[det.classIndex] ?? 1.0
            return Double(det.confidence * w)
        }.max() ?? 0.0

        // bbox_area = sum of person+bicycle detection areas as a frame fraction (0–1).
        // Restricted to cycling-relevant classes so a large passing car doesn't inflate the score.
        let bboxArea = detections.reduce(0.0) { sum, det in
            Self.bboxAreaClasses.contains(det.classIndex)
                ? sum + Double(det.boundingBox.width * det.boundingBox.height)
                : sum
        }

        return (detections, detectScore, bboxArea)
    }

    // MARK: - Pixel buffer

    private static func pixelBuffer(from cgImage: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32ARGB, attrs as CFDictionary, &buffer)
        guard let pb = buffer else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pb),
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        ctx?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(pb, [])
        return pb
    }

    // MARK: - YOLO decode

    // Candidate before NMS
    private struct Cand {
        let cls: Int
        let conf: Float
        let cx, cy, w, h: Float
    }

    /// Decode raw YOLO output [1, numVals, numAnchors] where numVals = 4 + numClasses.
    /// Box coords (cx, cy, w, h) are in pixel space [0, 640].
    private func decodeYOLO(_ raw: MLMultiArray) -> [YOLODetection] {
        let shape = raw.shape.map { $0.intValue }
        guard shape.count == 3, shape[0] >= 1 else { return [] }
        let nVals    = shape[1]
        let nAnchors = shape[2]

        let s1 = raw.strides[1].intValue
        let s2 = raw.strides[2].intValue
        let s = GlobalSettings.shared
        let peopleThreshold  = Float(s.yoloMinConfidence)
        let vehicleThreshold = Float(s.yoloVehicleConfidence)

        var cands: [Cand] = []
        cands.reserveCapacity(512)

        switch raw.dataType {
        case .float32:
            let ptr = raw.dataPointer.assumingMemoryBound(to: Float32.self)
            for a in 0..<nAnchors {
                var bestConf: Float = 0
                var bestCls  = -1
                for v in 4..<nVals {
                    let cls = v - 4
                    guard Self.classWeights[cls] != nil else { continue }
                    let val = ptr[s1 * v + s2 * a]
                    if val > bestConf { bestConf = val; bestCls = cls }
                }
                guard bestCls >= 0 else { continue }
                let threshold = Self.vehicleClasses.contains(bestCls) ? vehicleThreshold : peopleThreshold
                guard bestConf >= threshold else { continue }
                cands.append(Cand(
                    cls: bestCls, conf: bestConf,
                    cx: ptr[s2 * a],
                    cy: ptr[s1 + s2 * a],
                    w:  ptr[s1 * 2 + s2 * a],
                    h:  ptr[s1 * 3 + s2 * a]
                ))
            }
        default:
            // Fallback: use subscript (slow but handles any dataType)
            for a in 0..<nAnchors {
                var bestConf: Float = 0
                var bestCls  = -1
                for v in 4..<nVals {
                    let cls = v - 4
                    guard Self.classWeights[cls] != nil else { continue }
                    let val = Float(truncating: raw[[0, v, a] as [NSNumber]])
                    if val > bestConf { bestConf = val; bestCls = cls }
                }
                guard bestCls >= 0 else { continue }
                let threshold = Self.vehicleClasses.contains(bestCls) ? vehicleThreshold : peopleThreshold
                guard bestConf >= threshold else { continue }
                cands.append(Cand(
                    cls: bestCls, conf: bestConf,
                    cx: Float(truncating: raw[[0, 0, a] as [NSNumber]]),
                    cy: Float(truncating: raw[[0, 1, a] as [NSNumber]]),
                    w:  Float(truncating: raw[[0, 2, a] as [NSNumber]]),
                    h:  Float(truncating: raw[[0, 3, a] as [NSNumber]])
                ))
            }
        }

        // Per-class NMS
        var results: [YOLODetection] = []
        for cls in Set(cands.map(\.cls)) {
            var pool = cands.filter { $0.cls == cls }.sorted { $0.conf > $1.conf }
            while !pool.isEmpty {
                let best = pool.removeFirst()
                results.append(makeDetection(best))
                pool.removeAll { iou(best, $0) >= 0.45 }
            }
        }
        return results
    }

    private func makeDetection(_ c: Cand) -> YOLODetection {
        let s  = Float(AppConfig.yoloImageSize)
        let x  = CGFloat((c.cx - c.w / 2) / s)
        let y  = CGFloat((c.cy - c.h / 2) / s)
        let bw = CGFloat(c.w / s)
        let bh = CGFloat(c.h / s)
        return YOLODetection(
            className:   Self.classNames[c.cls] ?? "",
            classIndex:  c.cls,
            confidence:  c.conf,
            boundingBox: CGRect(
                x: max(0, x), y: max(0, y),
                width: min(1 - max(0, x), bw),
                height: min(1 - max(0, y), bh)
            )
        )
    }

    private func iou(_ a: Cand, _ b: Cand) -> Float {
        let ax1 = a.cx - a.w / 2;  let ay1 = a.cy - a.h / 2
        let ax2 = a.cx + a.w / 2;  let ay2 = a.cy + a.h / 2
        let bx1 = b.cx - b.w / 2;  let by1 = b.cy - b.h / 2
        let bx2 = b.cx + b.w / 2;  let by2 = b.cy + b.h / 2
        let iw  = max(0, min(ax2, bx2) - max(ax1, bx1))
        let ih  = max(0, min(ay2, by2) - max(ay1, by1))
        let inter = iw * ih
        let union = a.w * a.h + b.w * b.h - inter
        return union > 0 ? inter / union : 0
    }
}
