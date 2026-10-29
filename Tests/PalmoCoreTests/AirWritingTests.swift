import Foundation
import Testing
@testable import PalmoCore

/// A face centered in the frame, with eye corners where Vision usually puts them.
private let face = FaceGeometry(rect: Rect2D(minX: 0.35, minY: 0.35, width: 0.3, height: 0.4),
                                leftEyeOuter: Point2D(x: 0.39, y: 0.60), rightEyeOuter: Point2D(x: 0.61, y: 0.60))

/// A pointing hand whose index fingertip is at `tip`.
private func pointing(tipAt tip: Point2D) -> HandPose {
    let base = HandFixture.pointing()
    return HandFixture.pointing(offset: tip - base[.indexTip])
}

/// A pinching hand whose pen point (between thumb and index tips) is at `pen`.
private func pinch(at pen: Point2D) -> HandPose {
    let base = HandFixture.pinch()
    return HandFixture.pinch(offset: pen - Point2D.midpoint(base[.thumbTip], base[.indexTip]))
}

@Suite("Temple detection")
struct TempleTests {
    let detector = TempleDetector()

    @Test("Zones sit just outside the outer eye corners, slightly above")
    func zoneGeometry() {
        let zones = detector.zones(for: face)
        #expect(zones.count == 2)
        let left = zones.first { $0.side == .left }!, right = zones.first { $0.side == .right }!
        #expect(left.center.x < 0.39 && right.center.x > 0.61)
        #expect(left.center.y > 0.60 && right.center.y > 0.60)
        #expect(!left.contains(Point2D(x: 0.5, y: 0.6)) && !right.contains(Point2D(x: 0.5, y: 0.6)))
    }

    @Test("Without landmarks the zones fall back to the face box sides")
    func zoneFallback() {
        let zones = detector.zones(for: FaceGeometry(rect: face.rect))
        let left = zones.first { $0.side == .left }!
        #expect(abs(left.center.x - 0.356) < 0.02)
        #expect(left.center.y > 0.55 && left.center.y < 0.65)
    }

    @Test("Index fingertip at either temple is detected")
    func touchDetected() {
        #expect(detector.touchedSide(pose: pointing(tipAt: Point2D(x: 0.36, y: 0.625)), face: face) == .left)
        #expect(detector.touchedSide(pose: pointing(tipAt: Point2D(x: 0.64, y: 0.625)), face: face) == .right)
    }

    @Test("Nose, mouth, chin, forehead center and far away don't count",
          arguments: [Point2D(x: 0.5, y: 0.52), Point2D(x: 0.5, y: 0.43), Point2D(x: 0.5, y: 0.36),
                      Point2D(x: 0.5, y: 0.72), Point2D(x: 0.2, y: 0.6), Point2D(x: 0.4, y: 0.42)])
    func elsewhereIgnored(_ tip: Point2D) {
        #expect(detector.touchedSide(pose: pointing(tipAt: tip), face: face) == nil)
    }

    @Test("A curled index (fist resting at the temple) doesn't count")
    func curledIgnored() {
        let fist = HandFixture.fist()
        let moved = HandFixture.pose(index: .curled, middle: .curled, ring: .curled, little: .curled, thumb: .tucked,
                                     offset: Point2D(x: 0.36, y: 0.625) - fist[.indexTip])
        #expect(detector.touchedSide(pose: moved, face: face) == nil)
    }

    @Test("The temple hold needs about 0.6 s, tolerates a blip, and fires once per touch")
    func holdTiming() {
        var hold = GestureHold(dwell: 0.6, grace: 0.15, cooldown: 1.2)
        var fired: [Double] = []
        for i in 0..<60 {
            let t = Double(i) / 30
            let touching = i != 8 // one dropped frame
            if hold.update(active: touching, at: t) { fired.append(t) }
        }
        #expect(fired.count == 1)
        #expect(fired[0] >= 0.59 && fired[0] < 0.7)
        // A brief brush doesn't fire.
        var brush = GestureHold(dwell: 0.6)
        #expect(!(0..<10).map { brush.update(active: true, at: Double($0) / 30) }.contains(true))
    }
}

@Suite("Stroke segmentation")
struct StrokeTests {
    @Test("Pen down/up produce strokes; a pause ends the word")
    func strokesAndWords() {
        var seg = StrokeSegmenter(wordPause: 1.0)
        var t = 0.0, words: [[[Point2D]]] = []
        func step(_ down: Bool, _ x: Double) {
            t += 1.0 / 30
            if let w = seg.update(penDown: down, at: Point2D(x: x, y: 0.5), time: t) { words.append(w) }
        }
        for i in 0..<15 { step(true, 0.3 + Double(i) * 0.01) }
        for _ in 0..<5 { step(false, 0.45) }
        for i in 0..<15 { step(true, 0.5 + Double(i) * 0.01) }
        #expect(seg.strokes.count == 1 && seg.isPenDown)
        for _ in 0..<45 { step(false, 0.6) }
        #expect(words.count == 1)
        #expect(words[0].count == 2)
        #expect(seg.strokes.isEmpty)
    }

    @Test("A one-frame flicker neither starts nor breaks a stroke")
    func debounced() {
        var seg = StrokeSegmenter()
        var t = 0.0
        func step(_ down: Bool) { t += 1.0 / 30; _ = seg.update(penDown: down, at: Point2D(x: t, y: 0.5), time: t) }
        step(true); step(false); step(false)
        #expect(!seg.isPenDown && seg.strokes.isEmpty)
        for _ in 0..<10 { step(true) }
        step(false); step(true); step(true)
        #expect(seg.isPenDown && seg.strokes.isEmpty)
    }

    @Test("Losing the hand lifts the pen")
    func handLossLifts() {
        var seg = StrokeSegmenter()
        var t = 0.0
        for i in 0..<10 { t += 1.0 / 30; _ = seg.update(penDown: true, at: Point2D(x: Double(i) * 0.01, y: 0.5), time: t) }
        for _ in 0..<4 { t += 1.0 / 30; _ = seg.update(penDown: true, at: nil, time: t) }
        #expect(!seg.isPenDown && seg.strokes.count == 1)
    }
}

@Suite("Air-writing session")
struct AirSessionTests {
    /// Drives a session at 30 fps.
    struct Driver {
        var session = AirWritingSession(wordPause: 0.8)
        var t = 0.0
        @discardableResult
        mutating func feed(_ seconds: Double, _ make: (Double) -> HandPose?) -> [AirWritingEvent] {
            var events: [AirWritingEvent] = []
            let n = Int((seconds * 30).rounded())
            for i in 0..<n { t += 1.0 / 30; events += session.process(make(Double(i) / Double(max(n - 1, 1))), at: t) }
            return events
        }
        mutating func writeStroke() -> [AirWritingEvent] {
            feed(0.4) { pinch(at: Point2D(x: 0.4 + $0 * 0.1, y: 0.5)) }
        }
    }

    @Test("Pinch writes; a pause sends the word for recognition")
    func pinchAndPause() {
        var d = Driver()
        var events = d.writeStroke()
        #expect(d.session.segmenter.inkStrokes.count == 1)
        events += d.feed(1.0) { _ in HandFixture.openPalm() }
        let ids = events.compactMap { if case .recognize(let id, let strokes) = $0, !strokes.isEmpty { id } else { nil } }
        #expect(ids == [1])
        #expect(d.session.pendingWords == 1)
        _ = d.session.complete(id: 1, text: "hello")
        #expect(d.session.preview == "hello")
    }

    @Test("Thumbs-up types the preview with a trailing space, waiting for pending words")
    func thumbsUpInserts() {
        var d = Driver()
        d.writeStroke()
        d.feed(1.0) { _ in HandFixture.openPalm() }
        _ = d.session.complete(id: 1, text: "hello")
        d.writeStroke()
        let thumbs = d.feed(0.8) { _ in HandFixture.thumbsUp() }
        #expect(!thumbs.contains { if case .insert = $0 { true } else { false } })
        #expect(thumbs.contains { if case .recognize(2, _) = $0 { true } else { false } })
        let done = d.session.complete(id: 2, text: "world")
        #expect(done == [.insert("hello world ")])
        #expect(d.session.preview.isEmpty)
    }

    @Test("Two fingers delete the last word")
    func deleteWord() {
        var d = Driver()
        d.writeStroke()
        d.feed(1.0) { _ in HandFixture.openPalm() }
        _ = d.session.complete(id: 1, text: "oops")
        let events = d.feed(0.7) { _ in HandFixture.twoFingers() }
        #expect(events.contains(.deletedWord))
        #expect(d.session.preview.isEmpty)
    }

    @Test("A fist hold cancels; a brief fist doesn't")
    func fistCancels() {
        var d = Driver()
        #expect(!d.feed(0.3) { _ in HandFixture.fist() }.contains(.cancel))
        d.feed(0.3) { _ in HandFixture.openPalm() }
        #expect(d.feed(0.9) { _ in HandFixture.fist() }.contains(.cancel))
    }

    @Test("Unreadable words are dropped")
    func emptyResultDropped() {
        var d = Driver()
        d.writeStroke()
        d.feed(1.0) { _ in nil }
        _ = d.session.complete(id: 1, text: nil)
        #expect(d.session.pendingWords == 0 && d.session.preview.isEmpty)
    }
}

/// Single-stroke letter shapes (x right, y up; baseline 0, x-height 0.5, ascender 1) for synthetic handwriting.
enum SyntheticInk {
    static func arc(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ a0: Double, _ a1: Double, n: Int = 14) -> [Point2D] {
        (0...n).map { i in
            let a = (a0 + (a1 - a0) * Double(i) / Double(n)) * .pi / 180
            return Point2D(x: cx + rx * cos(a), y: cy + ry * sin(a))
        }
    }
    static let glyphs: [Character: (Double, [[Point2D]])] = [
        "h": (0.5, [[.init(x: 0, y: 1), .init(x: 0, y: 0)], [.init(x: 0, y: 0.3)] + arc(0.25, 0.3, 0.25, 0.2, 180, 0) + [.init(x: 0.5, y: 0)]]),
        "e": (0.5, [[.init(x: 0.02, y: 0.25), .init(x: 0.5, y: 0.25)] + arc(0.25, 0.25, 0.25, 0.25, 0, 330)]),
        "l": (0.15, [[.init(x: 0.05, y: 1), .init(x: 0.05, y: 0)]]),
        "o": (0.5, [arc(0.25, 0.25, 0.25, 0.25, 90, 450, n: 20)]),
        "w": (0.7, [[.init(x: 0, y: 0.5), .init(x: 0.17, y: 0), .init(x: 0.35, y: 0.4), .init(x: 0.53, y: 0), .init(x: 0.7, y: 0.5)]]),
        "r": (0.35, [[.init(x: 0, y: 0.5), .init(x: 0, y: 0)], [.init(x: 0, y: 0.3)] + arc(0.2, 0.3, 0.2, 0.2, 180, 60)]),
        "d": (0.5, [arc(0.25, 0.25, 0.25, 0.25, 90, 450, n: 20), [.init(x: 0.5, y: 1), .init(x: 0.5, y: 0)]]),
        "c": (0.45, [arc(0.25, 0.25, 0.25, 0.25, 45, 315)]),
        "a": (0.5, [arc(0.25, 0.25, 0.25, 0.25, 90, 450, n: 20), [.init(x: 0.5, y: 0.5), .init(x: 0.5, y: 0)]]),
        "t": (0.35, [[.init(x: 0.15, y: 0.9), .init(x: 0.15, y: 0)], [.init(x: 0, y: 0.55), .init(x: 0.35, y: 0.55)]]),
        "i": (0.1, [[.init(x: 0.05, y: 0.5), .init(x: 0.05, y: 0)], [.init(x: 0.05, y: 0.7)]]),
        "n": (0.5, [[.init(x: 0, y: 0.5), .init(x: 0, y: 0)], [.init(x: 0, y: 0.3)] + arc(0.25, 0.3, 0.25, 0.2, 180, 0) + [.init(x: 0.5, y: 0)]]),
    ]

    /// Strokes for `word` in camera space (about 0.1 tall), with deterministic wobble.
    static func strokes(_ word: String, wobble: Double = 0.02, seed: UInt64 = 1) -> [[Point2D]] {
        var state = seed
        func noise() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return (Double(state >> 33) / Double(1 << 31) - 0.5) * 2 * wobble
        }
        var x = 0.0, out: [[Point2D]] = []
        for ch in word {
            let (w, strokes) = glyphs[ch]!
            for s in strokes {
                out.append(s.map { Point2D(x: 0.3 + (x + $0.x + noise()) * 0.1 / (4.0 / 3.0), y: 0.45 + ($0.y + noise()) * 0.1) })
            }
            x += w + 0.25
        }
        return out
    }
}

@Suite("Handwriting recognition (Vision)")
struct HandwritingTests {
    @Test("Synthetic ink renders to an image")
    func renders() throws {
        let image = try #require(HandwritingRecognizer.render(SyntheticInk.strokes("hi")))
        #expect(image.height == 128 && image.width > 100)
    }

    @Test("Synthetic handwritten words are read back")
    func recognizesWords() {
        let words = ["hello", "world", "cat", "note", "dance", "later", "hi", "tide"]
        var correct = 0
        for (i, word) in words.enumerated() {
            let text = HandwritingRecognizer.recognize(SyntheticInk.strokes(word, seed: UInt64(i + 1)))?.text.lowercased()
            if text == word { correct += 1 }
        }
        // Vision isn't a handwriting engine; require a strong majority rather than perfection.
        #expect(correct >= words.count - 2, "read \(correct) of \(words.count)")
    }
}
