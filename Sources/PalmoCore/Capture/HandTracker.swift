import CoreVideo
import Foundation
import Vision

/// Runs Vision hand-pose (and periodic face) detection on camera frames.
///
/// Not thread-safe by design: an instance is owned and used exclusively by the capture queue.
final class HandTracker {
    private let handRequest: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
        return request
    }()
    private let faceRequest = VNDetectFaceRectanglesRequest()
    private var frameIndex = 0
    private var lastFace: (rect: Rect2D, time: TimeInterval)?

    /// Vision joint names in `Joint` order.
    static let visionJoints: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip,
    ]

    /// Detects one hand (and, every sixth frame, the face). Coordinates are mirrored into user perspective.
    func process(_ pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) -> (pose: HandPose?, face: Rect2D?) {
        frameIndex &+= 1
        let runFace = frameIndex % 6 == 0
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform(runFace ? [handRequest, faceRequest] : [handRequest])
        } catch {
            return (nil, currentFace(at: timestamp))
        }
        if runFace {
            if let face = faceRequest.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width }) {
                let box = face.boundingBox
                lastFace = (Rect2D(minX: 1 - box.maxX, minY: box.minY, width: box.width, height: box.height), timestamp)
            } else {
                lastFace = nil
            }
        }
        guard let observation = handRequest.results?.first,
              let points = try? observation.recognizedPoints(.all) else {
            return (nil, currentFace(at: timestamp))
        }
        let landmarks: [Landmark] = Self.visionJoints.map { name in
            guard let point = points[name] else { return Landmark(location: Point2D(x: 0.5, y: 0.5), confidence: 0) }
            return Landmark(location: Point2D(x: 1 - point.location.x, y: point.location.y), confidence: Double(point.confidence))
        }
        let chirality: Chirality = switch observation.chirality {
        case .left: .left
        case .right: .right
        default: .unknown
        }
        return (HandPose(landmarks: landmarks, chirality: chirality, timestamp: timestamp), currentFace(at: timestamp))
    }

    private func currentFace(at time: TimeInterval) -> Rect2D? {
        guard let lastFace, time - lastFace.time < 1.0 else { return nil }
        return lastFace.rect
    }
}
