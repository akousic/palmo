import Foundation
import Testing
@testable import PalmoCore

@Suite("One Euro filter")
struct OneEuroFilterTests {
    @Test("First sample passes through unchanged")
    func firstSample() {
        var filter = OneEuroFilter()
        #expect(filter.filter(0.42, at: 0) == 0.42)
    }

    @Test("Converges to a constant signal")
    func converges() {
        var filter = OneEuroFilter(minCutoff: 1, beta: 0)
        _ = filter.filter(0, at: 0)
        var value = 0.0
        for i in 1...120 { value = filter.filter(1, at: Double(i) / 30) }
        #expect(abs(value - 1) < 0.01)
    }

    @Test("Reduces jitter on a noisy stationary signal")
    func smoothsJitter() {
        var filter = OneEuroFilter(minCutoff: 1, beta: 0.01)
        var generator = SplitMix(seed: 7)
        var raw: [Double] = [], smooth: [Double] = []
        for i in 0..<300 {
            let sample = 0.5 + (generator.nextUnit() - 0.5) * 0.02
            raw.append(sample)
            smooth.append(filter.filter(sample, at: Double(i) / 30))
        }
        #expect(variance(smooth.dropFirst(30)) < variance(raw.dropFirst(30)) / 4)
    }

    @Test("Tracks fast motion with little lag when beta is high")
    func fastMotion() {
        var filter = OneEuroFilter(minCutoff: 1, beta: 20)
        var output = 0.0
        for i in 0...30 { output = filter.filter(Double(i) / 30, at: Double(i) / 30) }
        #expect(abs(output - 1) < 0.1)
    }

    @Test("Hand smoother resets after a tracking gap")
    func smootherReset() {
        var smoother = HandPoseSmoother()
        _ = smoother.smooth(HandFixture.pose(index: .extended, middle: .curled, ring: .curled, little: .curled, thumb: .tucked, time: 0))
        let jumped = HandFixture.pose(index: .extended, middle: .curled, ring: .curled, little: .curled, thumb: .tucked,
                                      offset: Point2D(x: 0.3, y: 0), time: 2)
        let out = smoother.smooth(jumped)
        #expect(abs(out[.wrist].x - jumped[.wrist].x) < 1e-9)
    }

    private func variance<C: Collection>(_ values: C) -> Double where C.Element == Double {
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }
}

/// Deterministic random numbers for tests.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func nextUnit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

@Suite("Cursor mapper")
struct CursorMapperTests {
    let bounds = ScreenRect(minX: 0, minY: 0, maxX: 1000, maxY: 800)

    @Test("First sample only anchors")
    func anchors() {
        var mapper = CursorMapper()
        #expect(mapper.update(handPoint: Point2D(x: 0.5, y: 0.5), at: 0, cursor: (500, 400), bounds: bounds) == nil)
    }

    @Test("Moving the hand right and up moves the cursor right and up (screen y decreases)")
    func direction() throws {
        var mapper = CursorMapper()
        _ = mapper.update(handPoint: Point2D(x: 0.5, y: 0.5), at: 0, cursor: (500, 400), bounds: bounds)
        let nextOpt = mapper.update(handPoint: Point2D(x: 0.52, y: 0.52), at: 1.0 / 30, cursor: (500, 400), bounds: bounds)
        let next = try #require(nextOpt)
        #expect(next.x > 500)
        #expect(next.y < 400)
    }

    @Test("Faster motion moves further (acceleration)")
    func acceleration() throws {
        var slow = CursorMapper(smoothing: 0), fast = CursorMapper(smoothing: 0)
        _ = slow.update(handPoint: Point2D(x: 0.5, y: 0.5), at: 0, cursor: (500, 400), bounds: bounds)
        _ = fast.update(handPoint: Point2D(x: 0.5, y: 0.5), at: 0, cursor: (500, 400), bounds: bounds)
        let aOpt = slow.update(handPoint: Point2D(x: 0.51, y: 0.5), at: 0.2, cursor: (500, 400), bounds: bounds)
        let a = try #require(aOpt)
        let bOpt = fast.update(handPoint: Point2D(x: 0.51, y: 0.5), at: 0.02, cursor: (500, 400), bounds: bounds)
        let b = try #require(bOpt)
        #expect(b.x - 500 > a.x - 500)
    }

    @Test("Tiny jitter is ignored")
    func deadZone() {
        var mapper = CursorMapper()
        _ = mapper.update(handPoint: Point2D(x: 0.5, y: 0.5), at: 0, cursor: (500, 400), bounds: bounds)
        #expect(mapper.update(handPoint: Point2D(x: 0.5005, y: 0.5), at: 1.0 / 30, cursor: (500, 400), bounds: bounds) == nil)
    }

    @Test("Long gaps clutch instead of jumping")
    func clutch() {
        var mapper = CursorMapper()
        _ = mapper.update(handPoint: Point2D(x: 0.2, y: 0.5), at: 0, cursor: (500, 400), bounds: bounds)
        #expect(mapper.update(handPoint: Point2D(x: 0.8, y: 0.5), at: 1.0, cursor: (500, 400), bounds: bounds) == nil)
    }

    @Test("Cursor stays on screen")
    func clamps() throws {
        var mapper = CursorMapper(gain: 3)
        _ = mapper.update(handPoint: Point2D(x: 0.5, y: 0.5), at: 0, cursor: (990, 10), bounds: bounds)
        let nextOpt = mapper.update(handPoint: Point2D(x: 0.6, y: 0.6), at: 1.0 / 30, cursor: (990, 10), bounds: bounds)
        let next = try #require(nextOpt)
        #expect(next.x <= 1000 && next.y >= 0)
    }

    @Test("Slow hand motion is scaled down for precision; fast motion is scaled up")
    func precisionCurve() {
        let mapper = CursorMapper(precision: 0.35, acceleration: 1.6)
        #expect(abs(mapper.speedFactor(forSpeed: 0.01) - 0.35) < 1e-9)
        #expect(abs(mapper.speedFactor(forSpeed: 5) - 2.6) < 1e-9)
        #expect(mapper.speedFactor(forSpeed: 0.3) > 0.35 && mapper.speedFactor(forSpeed: 0.3) < 2.6)
        // Monotonic.
        var previous = 0.0
        for speed in stride(from: 0.0, through: 1.0, by: 0.05) {
            let f = mapper.speedFactor(forSpeed: speed)
            #expect(f >= previous)
            previous = f
        }
    }

    @Test("A slow sweep covers less screen per unit of hand travel than a fast one")
    func slowSweepIsFiner() {
        func travel(duration: Double) -> Double {
            var mapper = CursorMapper(smoothing: 0)
            var cursor = (x: 500.0, y: 400.0)
            let frames = Int(duration * 30)
            for i in 0...frames {
                let x = 0.4 + 0.05 * Double(i) / Double(frames)
                if let next = mapper.update(handPoint: Point2D(x: x, y: 0.5), at: Double(i) / 30, cursor: cursor, bounds: bounds) {
                    cursor = next
                }
            }
            return cursor.x - 500
        }
        let slow = travel(duration: 2.0)   // 0.025 units/s
        let fast = travel(duration: 0.1)   // 0.5 units/s
        #expect(slow > 0)
        #expect(fast > slow * 2)
    }

    @Test("Smoothing steadies a jittery, nearly still hand")
    func smoothingReducesJitter() {
        func spread(smoothing: Double) -> Double {
            var mapper = CursorMapper(smoothing: smoothing, deadZone: 0)
            var cursor = (x: 500.0, y: 400.0)
            var xs: [Double] = []
            for i in 0..<90 {
                let jitter = (i % 2 == 0 ? 1.0 : -1.0) * 0.003
                if let next = mapper.update(handPoint: Point2D(x: 0.5 + jitter, y: 0.5), at: Double(i) / 30, cursor: cursor, bounds: bounds) {
                    cursor = next
                }
                xs.append(cursor.x)
            }
            return (xs.max() ?? 0) - (xs.min() ?? 0)
        }
        #expect(spread(smoothing: 1) < spread(smoothing: 0) / 2)
    }

    @Test("Holding tracks the hand without moving, so the next move doesn't jump")
    func holdReanchors() throws {
        var mapper = CursorMapper(smoothing: 0)
        _ = mapper.update(handPoint: Point2D(x: 0.5, y: 0.5), at: 0, cursor: (500, 400), bounds: bounds)
        mapper.hold(handPoint: Point2D(x: 0.6, y: 0.5), at: 0.033)
        let nextOpt = mapper.update(handPoint: Point2D(x: 0.601, y: 0.5), at: 0.066, cursor: (500, 400), bounds: bounds)
        let next = try #require(nextOpt)
        #expect(next.x - 500 < 5)
    }
}
