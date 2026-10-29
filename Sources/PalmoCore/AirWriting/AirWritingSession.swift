import Foundation

/// Something the air-writing session wants done.
public enum AirWritingEvent: Sendable, Equatable {
    /// Recognize these strokes and report back with `complete(id:text:)`.
    case recognize(id: Int, strokes: [[Point2D]])
    /// Type this text into the focused field.
    case insert(String)
    /// The last word was removed from the preview.
    case deletedWord
    /// The user cancelled (fist hold): leave air-writing mode.
    case cancel
}

/// Snapshot of air-writing for the overlay and menu.
public struct AirWritingStatus: Sendable, Equatable {
    /// Whether air-writing mode is on.
    public var isActive = false
    /// Ink of the word being written (normalized, y up).
    public var ink: [[Point2D]] = []
    /// Current pen position, if a hand is visible.
    public var penPoint: Point2D?
    /// Whether the pen is down.
    public var penDown = false
    /// Recognized text waiting to be typed.
    public var preview = ""
    /// Words still being recognized.
    public var pendingWords = 0
    /// Progress `0...1` of a temple-touch hold.
    public var templeProgress: Double = 0
    /// The last text typed.
    public var lastInserted: String?

    /// Creates an inactive status.
    public init() {}

    func with(lastInserted: String?) -> AirWritingStatus {
        var copy = self
        copy.lastInserted = lastInserted
        return copy
    }
}

/// The air-writing state machine. Pure and synchronous, so it is unit-testable; recognition and typing are
/// done by the caller in response to events.
///
/// Gestures while writing:
/// - **Pinch** (thumb on index) = pen down; release = pen up. The pen is the point between thumb and index tips.
/// - Pen up for `wordPause` seconds = the word is recognized and added to the preview.
/// - **Thumbs-up** hold = type the preview (plus a trailing space).
/// - **Two fingers / V** hold = delete the last word (or the word being written).
/// - **Fist** hold = cancel and leave air writing.
public struct AirWritingSession: Sendable {
    /// Pinch gap (hand sizes) below which the pen goes down, and above which it lifts.
    public var penDownGap = 0.30
    public var penUpGap = 0.45

    /// Stroke and word segmentation.
    public private(set) var segmenter: StrokeSegmenter
    private var slots: [(id: Int, text: String?)] = []
    private var nextID = 1
    private var insertRequested = false
    private var pinched = false
    private let classifier = PoseClassifier()
    private var thumbsHold = GestureHold(dwell: 0.45, cooldown: 1.0)
    private var deleteHold = GestureHold(dwell: 0.5, cooldown: 0.8)
    private var fistHold = GestureHold(dwell: 0.7)
    /// Latest pen position.
    public private(set) var penPoint: Point2D?

    /// Creates a session.
    public init(wordPause: Double = 1.0) {
        segmenter = StrokeSegmenter(wordPause: wordPause)
    }

    /// Recognized text waiting to be typed.
    public var preview: String { slots.compactMap(\.text).joined(separator: " ") }
    /// Number of words still being recognized.
    public var pendingWords: Int { slots.filter { $0.text == nil }.count }

    /// Processes one frame.
    public mutating func process(_ pose: HandPose?, at t: TimeInterval) -> [AirWritingEvent] {
        var events: [AirWritingEvent] = []
        var point: Point2D?
        if let pose {
            let gap = PoseMetrics(pose).thumbIndexGap
            pinched = pinched ? gap < penUpGap : gap < penDownGap
            point = Point2D.midpoint(pose[.thumbTip], pose[.indexTip])
        } else {
            pinched = false
        }
        penPoint = point
        if let word = segmenter.update(penDown: pinched, at: point, time: t) { events.append(enqueue(word)) }

        let shape: HandShape = (pose != nil && !segmenter.isPenDown && !pinched) ? classifier.classify(pose!) : .unknown
        if thumbsHold.update(active: shape == .thumbsUp, at: t) {
            if let word = segmenter.flush() { events.append(enqueue(word)) }
            insertRequested = true
        }
        if deleteHold.update(active: shape == .twoFingers || shape == .peace, at: t) {
            if !segmenter.inkStrokes.isEmpty { segmenter.clear() } else if !slots.isEmpty { slots.removeLast() }
            events.append(.deletedWord)
        }
        if fistHold.update(active: shape == .fist, at: t) {
            events.append(.cancel)
            return events
        }
        events += flushInsertIfReady()
        return events
    }

    /// Delivers a recognition result. `nil` or empty text drops the word.
    public mutating func complete(id: Int, text: String?) -> [AirWritingEvent] {
        guard let index = slots.firstIndex(where: { $0.id == id }) else { return [] }
        let clean = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if clean.isEmpty { slots.remove(at: index) } else { slots[index].text = clean }
        return flushInsertIfReady()
    }

    /// Requests typing the preview as soon as pending words are recognized (thumbs-up equivalent).
    public mutating func requestInsert() -> [AirWritingEvent] {
        var events: [AirWritingEvent] = []
        if let word = segmenter.flush() { events.append(enqueue(word)) }
        insertRequested = true
        return events + flushInsertIfReady()
    }

    /// Snapshot for display.
    public var status: AirWritingStatus {
        var s = AirWritingStatus()
        s.isActive = true
        s.ink = segmenter.inkStrokes
        s.penPoint = penPoint
        s.penDown = segmenter.isPenDown
        s.preview = preview
        s.pendingWords = pendingWords
        return s
    }

    /// Changes the word pause.
    public mutating func setWordPause(_ seconds: Double) { segmenter.wordPause = seconds }

    private mutating func enqueue(_ strokes: [[Point2D]]) -> AirWritingEvent {
        let id = nextID
        nextID += 1
        slots.append((id, nil))
        return .recognize(id: id, strokes: strokes)
    }

    private mutating func flushInsertIfReady() -> [AirWritingEvent] {
        guard insertRequested, pendingWords == 0 else { return [] }
        insertRequested = false
        let text = preview
        slots.removeAll()
        return text.isEmpty ? [] : [.insert(text + " ")]
    }
}
