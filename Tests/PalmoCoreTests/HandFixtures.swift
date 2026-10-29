import Foundation
@testable import PalmoCore

/// Builds synthetic, anatomically plausible hand poses for tests. Hand size (wrist → middle knuckle) is 0.15.
enum HandFixture {
    enum FingerState { case extended, curled }
    enum ThumbState { case tucked, out, up, pinchIndex, pinchMiddle, nearIndex(gap: Double) }

    static let wrist = Point2D(x: 0.5, y: 0.30)
    static let mcps: [Finger: Point2D] = [
        .index: Point2D(x: 0.45, y: 0.45), .middle: Point2D(x: 0.49, y: 0.45),
        .ring: Point2D(x: 0.53, y: 0.45), .little: Point2D(x: 0.57, y: 0.444),
    ]

    /// Returns a pose. `tipSpread` pushes extended fingertips away from the hand's centre line.
    static func pose(index: FingerState, middle: FingerState, ring: FingerState, little: FingerState,
                     thumb: ThumbState, tipSpread: Double = 0.8, vSpread: Double = 0,
                     offset: Point2D = Point2D(x: 0, y: 0), scale: Double = 1, rotation: Double = 0,
                     flipped: Bool = false, confidence: Double = 0.9, time: TimeInterval = 0) -> HandPose {
        var points = [Point2D](repeating: wrist, count: 21)
        let states: [Finger: FingerState] = [.index: index, .middle: middle, .ring: ring, .little: little]
        for finger in Finger.allCases {
            let mcp = mcps[finger]!
            points[finger.mcp.rawValue] = mcp
            switch states[finger]! {
            case .extended:
                var dx = (mcp.x - 0.51) * tipSpread
                if finger == .index { dx -= vSpread }
                if finger == .middle { dx += vSpread }
                points[finger.pip.rawValue] = mcp + Point2D(x: dx * 0.45, y: 0.05)
                points[finger.dip.rawValue] = mcp + Point2D(x: dx * 0.75, y: 0.08)
                points[finger.tip.rawValue] = mcp + Point2D(x: dx, y: 0.11)
            case .curled:
                points[finger.pip.rawValue] = mcp + Point2D(x: 0, y: 0.04)
                points[finger.dip.rawValue] = mcp + Point2D(x: 0, y: 0.0)
                points[finger.tip.rawValue] = mcp + Point2D(x: 0, y: -0.03)
            }
        }
        points[Joint.thumbCMC.rawValue] = Point2D(x: 0.46, y: 0.33)
        points[Joint.thumbMP.rawValue] = Point2D(x: 0.43, y: 0.37)
        points[Joint.thumbIP.rawValue] = Point2D(x: 0.41, y: 0.40)
        let thumbTip: Point2D = switch thumb {
        case .tucked: Point2D(x: 0.50, y: 0.42)
        case .out: Point2D(x: 0.33, y: 0.42)
        case .up: Point2D(x: 0.40, y: 0.56)
        case .pinchIndex: points[Joint.indexTip.rawValue] + Point2D(x: 0.005, y: 0)
        case .pinchMiddle: points[Joint.middleTip.rawValue] + Point2D(x: 0.005, y: 0)
        case .nearIndex(let gap): points[Joint.indexTip.rawValue] + Point2D(x: -gap * 0.15, y: 0)
        }
        points[Joint.thumbTip.rawValue] = thumbTip

        let transformed = points.map { p -> Point2D in
            var v = p - wrist
            if flipped { v = Point2D(x: -v.x, y: v.y) }
            let c = cos(rotation), s = sin(rotation)
            v = Point2D(x: v.x * c - v.y * s, y: v.x * s + v.y * c)
            return wrist + v * scale + offset
        }
        return HandPose(landmarks: transformed.map { Landmark(location: $0, confidence: confidence) },
                        chirality: .right, timestamp: time)
    }

    static func openPalm(offset: Point2D = Point2D(x: 0, y: 0), flipped: Bool = false) -> HandPose {
        pose(index: .extended, middle: .extended, ring: .extended, little: .extended, thumb: .out, offset: offset, flipped: flipped)
    }
    static func fist() -> HandPose { pose(index: .curled, middle: .curled, ring: .curled, little: .curled, thumb: .tucked) }
    static func pointing(offset: Point2D = Point2D(x: 0, y: 0)) -> HandPose {
        pose(index: .extended, middle: .curled, ring: .curled, little: .curled, thumb: .tucked, offset: offset)
    }
    static func pinch(offset: Point2D = Point2D(x: 0, y: 0)) -> HandPose {
        pose(index: .extended, middle: .curled, ring: .curled, little: .curled, thumb: .pinchIndex, offset: offset)
    }
    static func middlePinch() -> HandPose {
        pose(index: .extended, middle: .extended, ring: .curled, little: .curled, thumb: .pinchMiddle, tipSpread: 0, vSpread: 0.04)
    }
    static func twoFingers(offset: Point2D = Point2D(x: 0, y: 0)) -> HandPose {
        pose(index: .extended, middle: .extended, ring: .curled, little: .curled, thumb: .tucked, tipSpread: 0, offset: offset)
    }
    static func peace(offset: Point2D = Point2D(x: 0, y: 0)) -> HandPose {
        pose(index: .extended, middle: .extended, ring: .curled, little: .curled, thumb: .tucked, tipSpread: 0, vSpread: 0.04, offset: offset)
    }
    static func threeFingers(offset: Point2D = Point2D(x: 0, y: 0)) -> HandPose {
        pose(index: .extended, middle: .extended, ring: .extended, little: .curled, thumb: .tucked, offset: offset)
    }
    static func thumbOut(offset: Point2D = Point2D(x: 0, y: 0)) -> HandPose {
        pose(index: .curled, middle: .curled, ring: .curled, little: .curled, thumb: .out, offset: offset)
    }
    static func thumbsUp() -> HandPose { pose(index: .curled, middle: .curled, ring: .curled, little: .curled, thumb: .up) }
    static func dial(rotation: Double = 0) -> HandPose {
        pose(index: .extended, middle: .extended, ring: .extended, little: .extended, thumb: .pinchIndex, rotation: rotation)
    }
}

/// Drives a recognizer through timed frames.
struct RecognizerDriver {
    var recognizer: GestureRecognizer
    var time: TimeInterval = 0
    var context = RecognitionContext()
    static let frame = 1.0 / 30

    init(settings: PalmoSettings = .default) {
        recognizer = GestureRecognizer(configuration: RecognizerConfiguration(settings: settings))
    }

    /// Feeds poses produced by `make(progress 0...1)` for `duration` seconds and returns all events.
    @discardableResult
    mutating func feed(_ duration: Double, _ make: (Double) -> HandPose?) -> [GestureEvent] {
        var events: [GestureEvent] = []
        let frames = max(1, Int((duration / Self.frame).rounded()))
        for i in 0..<frames {
            time += Self.frame
            events += recognizer.process(make(Double(i + 1) / Double(frames)), at: time, context: context)
        }
        return events
    }

    @discardableResult
    mutating func hold(_ pose: HandPose?, for duration: Double) -> [GestureEvent] {
        feed(duration) { _ in pose }
    }

    /// Arms with an open palm and returns the events.
    @discardableResult
    mutating func arm() -> [GestureEvent] { hold(HandFixture.openPalm(), for: 1.0) }
}

extension Array where Element == GestureEvent {
    var gestures: [Gesture] { compactMap { if case .gesture(let g) = $0 { g } else { nil } } }
}
