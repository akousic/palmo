import Foundation

/// Turns a per-frame pen state into strokes, and groups strokes into words separated by pauses.
public struct StrokeSegmenter: Sendable {
    /// Seconds the pen must stay up before the current strokes become a word.
    public var wordPause: Double
    /// Minimum distance between recorded points (normalized image units).
    public var minPointSpacing = 0.002
    /// Consecutive frames needed to put the pen down / lift it (debounces flicker).
    public var downFrames = 2
    public var upFrames = 3

    /// Finished strokes of the word being written.
    public private(set) var strokes: [[Point2D]] = []
    /// The stroke being drawn, if the pen is down.
    public private(set) var current: [Point2D]?
    /// Whether the pen is (debounced) down.
    public var isPenDown: Bool { current != nil }
    /// All strokes of the current word, including the one in progress.
    public var inkStrokes: [[Point2D]] { strokes + (current.map { [$0] } ?? []) }

    private var pendingFrames = 0
    private var pendingPoints = 0
    private var lastPenUp: TimeInterval?

    /// Creates a segmenter.
    public init(wordPause: Double = 1.0) {
        self.wordPause = wordPause
    }

    /// Feeds one frame. `point` is the pen position, or `nil` when no hand is visible (pen up).
    /// Returns a finished word's strokes when the pen has been up for `wordPause`.
    public mutating func update(penDown requested: Bool, at point: Point2D?, time: TimeInterval) -> [[Point2D]]? {
        let wantDown = requested && point != nil
        if wantDown != isPenDown {
            pendingFrames += 1
            if wantDown, pendingFrames >= downFrames, let point {
                current = [point]
                pendingFrames = 0
                pendingPoints = 0
            } else if !wantDown, pendingFrames >= upFrames, let stroke = current {
                // Drop the tail recorded while the pen was already lifting.
                let kept = Array(stroke.dropLast(min(pendingPoints, max(stroke.count - 1, 0))))
                strokes.append(kept)
                current = nil
                pendingFrames = 0
                lastPenUp = time
            }
        } else {
            pendingFrames = 0
            pendingPoints = 0
        }
        if isPenDown, let point, let last = current?.last, point.distance(to: last) >= minPointSpacing {
            current?.append(point)
            if !wantDown { pendingPoints += 1 }
        }
        if !isPenDown, !strokes.isEmpty, let lastPenUp, time - lastPenUp >= wordPause {
            return flush()
        }
        return nil
    }

    /// Ends the current word now and returns its strokes, if any.
    public mutating func flush() -> [[Point2D]]? {
        if let current { strokes.append(current) }
        current = nil
        pendingFrames = 0
        defer { strokes = []; lastPenUp = nil }
        return strokes.isEmpty ? nil : strokes
    }

    /// Discards the current word.
    public mutating func clear() {
        strokes = []
        current = nil
        pendingFrames = 0
        lastPenUp = nil
    }
}
