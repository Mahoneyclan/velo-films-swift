import Foundation
import Vision
import CoreML
import CoreGraphics

/// Detection result for a single frame.
struct YOLODetection {
    var className: String
    var classIndex: Int
    var confidence: Float
    var boundingBox: CGRect   // normalised [0,1] coordinates
}

/// Core ML YOLO inference engine.
/// Mirrors object_detector.py: lazy load, batch processing, detect_score = max weighted conf.
final class YOLODetector {
    private var model: VNCoreMLModel?
    private let modelURL: URL

    /// Class weights — all 1.0 in the Python source (uniform importance).
    private static let classWeights: [Int: Float] = [
        0: 1.0,  // person
        1: 1.0,  // bicycle
        2: 1.0,  // car
        3: 1.0,  // motorcycle
        5: 1.0,  // bus
        7: 1.0,  // truck
        9: 1.0,  // traffic light
        11: 1.0, // stop sign
    ]

    init(modelURL: URL) {
        self.modelURL = modelURL
    }

    /// Lazy-load the Core ML model on first call.
    private func loadModel() throws -> VNCoreMLModel {
        if let model { return model }
        let mlModel = try MLModel(contentsOf: modelURL)
        let vnModel = try VNCoreMLModel(for: mlModel)
        self.model = vnModel
        return vnModel
    }

    /// Run inference on a single frame. Returns detections and the scalar detect_score.
    func detect(image: CGImage) throws -> (detections: [YOLODetection], detectScore: Double, bboxArea: Double) {
        let vnModel = try loadModel()

        var detections: [YOLODetection] = []
        let request = VNCoreMLRequest(model: vnModel) { request, _ in
            guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
            for obs in results {
                guard let label = obs.labels.first else { continue }
                guard obs.confidence >= AppConfig.yoloMinConfidence else { continue }
                // Map label to class index
                if let classIndex = Self.labelToIndex(label.identifier),
                   AppConfig.yoloDetectClasses.contains(classIndex) {
                    detections.append(YOLODetection(
                        className: label.identifier,
                        classIndex: classIndex,
                        confidence: obs.confidence,
                        boundingBox: obs.boundingBox
                    ))
                }
            }
        }
        request.imageCropAndScaleOption = .scaleFit

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        // detect_score = max(confidence × class_weight) across all boxes
        let detectScore = detections.map { det -> Double in
            let w = Self.classWeights[det.classIndex] ?? 1.0
            return Double(det.confidence * w)
        }.max() ?? 0.0

        // bbox_area = sum of normalised box areas × image pixel area
        let imgArea = Double(image.width * image.height)
        let bboxArea = detections.reduce(0.0) { sum, det in
            sum + Double(det.boundingBox.width * det.boundingBox.height) * imgArea
        }

        return (detections, detectScore, bboxArea)
    }

    private static func labelToIndex(_ label: String) -> Int? {
        let map: [String: Int] = [
            "person": 0, "bicycle": 1, "car": 2, "motorcycle": 3,
            "bus": 5, "truck": 7, "traffic light": 9, "stop sign": 11
        ]
        return map[label.lowercased()]
    }
}
