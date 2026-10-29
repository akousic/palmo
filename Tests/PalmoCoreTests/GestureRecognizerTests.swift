import Testing
@testable import PalmoCore

@Suite("Gesture recognizer")
struct GestureRecognizerTests {
    @Test("Arms only after holding an open palm for the dwell time")
    func armDwell() {
        var d = RecognizerDriver()
        #expect(!d.hold(HandFixture.openPalm(), for: 0.5).contains(.armed))
        #expect(!d.recognizer.isArmed)
        #expect(d.hold(HandFixture.openPalm(), for: 0.6).contains(.armed))
        #expect(d.recognizer.isArmed)
    }

    @Test("Does not arm while the user is typing")
    func typingGuardBlocksArming() {
        var d = RecognizerDriver()
        d.context.secondsSinceKeyboardInput = 0.1
        d.hold(HandFixture.openPalm(), for: 2)
        #expect(!d.recognizer.isArmed)
    }

    @Test("Ignores a hand inside the face zone")
    func faceZone() {
        var d = RecognizerDriver()
        d.context.faceRect = Rect2D(minX: 0.3, minY: 0.2, width: 0.4, height: 0.5)
        d.hold(HandFixture.openPalm(), for: 2)
        #expect(!d.recognizer.isArmed)
    }

    @Test("Holding a fist disarms")
    func fistDisarms() {
        var d = RecognizerDriver()
        d.arm()
        let events = d.hold(HandFixture.fist(), for: 1.3)
        #expect(events.contains(.disarmed(.gesture)))
        #expect(!d.recognizer.isArmed)
    }

    @Test("Disarms after the idle timeout")
    func idleDisarm() {
        var settings = PalmoSettings.default
        settings.idleDisarmSeconds = 5
        var d = RecognizerDriver(settings: settings)
        d.arm()
        let events = d.hold(nil, for: 5.5)
        #expect(events.contains(.disarmed(.idle)))
    }

    @Test("External disarm ends an active drag")
    func externalDisarmEndsDrag() {
        var d = RecognizerDriver()
        d.arm()
        d.hold(HandFixture.pinch(), for: 0.6)
        let events = d.recognizer.setArmed(false, at: d.time)
        #expect(events == [.dragEnded, .disarmed(.external)])
    }

    @Test("Pointing moves the pointer")
    func pointer() {
        var d = RecognizerDriver()
        d.arm()
        let events = d.feed(0.5) { p in HandFixture.pointing(offset: Point2D(x: p * 0.1, y: 0)) }
        #expect(events.contains { if case .pointer = $0 { true } else { false } })
    }

    @Test("A quick pinch clicks; two quick pinches double-click")
    func clicks() {
        var d = RecognizerDriver()
        d.arm()
        d.hold(HandFixture.pointing(), for: 0.3)
        d.hold(HandFixture.pinch(), for: 0.15)
        let first = d.hold(HandFixture.pointing(), for: 0.15)
        #expect(first.contains(.click(count: 1)))
        d.hold(HandFixture.pinch(), for: 0.15)
        let second = d.hold(HandFixture.pointing(), for: 0.15)
        #expect(second.contains(.click(count: 2)))
    }

    @Test("A held pinch drags and releases")
    func drag() {
        var d = RecognizerDriver()
        d.arm()
        d.hold(HandFixture.pointing(), for: 0.3)
        let during = d.feed(0.7) { p in HandFixture.pinch(offset: Point2D(x: p * 0.05, y: 0)) }
        #expect(during.contains(.dragBegan))
        #expect(during.contains { if case .dragMoved = $0 { true } else { false } })
        #expect(!during.contains(.click(count: 1)))
        #expect(d.hold(HandFixture.pointing(), for: 0.2).contains(.dragEnded))
    }

    @Test("Middle pinch right-clicks")
    func rightClick() {
        var d = RecognizerDriver()
        d.arm()
        #expect(d.hold(HandFixture.middlePinch(), for: 0.3).contains(.rightClick))
    }

    @Test("Two raised fingers scroll with hand motion")
    func scroll() {
        var d = RecognizerDriver()
        d.arm()
        let events = d.feed(0.6) { p in HandFixture.twoFingers(offset: Point2D(x: 0, y: p * 0.1)) }
        let dys = events.compactMap { if case .scroll(_, let dy) = $0 { dy } else { nil } }
        #expect(!dys.isEmpty)
        #expect(dys.allSatisfy { $0 > 0 })
    }

    @Test("Rotating the dial steps the volume")
    func dial() {
        var d = RecognizerDriver()
        d.arm()
        d.hold(HandFixture.dial(), for: 0.3)
        let events = d.feed(0.5) { p in HandFixture.dial(rotation: -p * 0.6) }
        let steps = events.compactMap { if case .volumeStep(let s) = $0 { s } else { nil } }
        #expect(steps.reduce(0, +) > 0)
    }

    @Test("Open-palm swipes in both directions")
    func swipes() {
        var d = RecognizerDriver()
        d.arm()
        let left = d.feed(0.3) { p in HandFixture.openPalm(offset: Point2D(x: -p * 0.3, y: 0)) }
        #expect(left.gestures == [.swipeLeft])
        d.hold(HandFixture.openPalm(offset: Point2D(x: -0.3, y: 0)), for: 1.0)
        let right = d.feed(0.3) { p in HandFixture.openPalm(offset: Point2D(x: -0.3 + p * 0.3, y: 0)) }
        #expect(right.gestures == [.swipeRight])
    }

    @Test("Three-finger flick, thumb flick and peace flick")
    func otherMotions() {
        var d = RecognizerDriver()
        d.arm()
        d.hold(HandFixture.threeFingers(), for: 0.3)
        #expect(d.feed(0.3) { p in HandFixture.threeFingers(offset: Point2D(x: 0, y: p * 0.2)) }.gestures == [.threeFingerUp])
        d.hold(HandFixture.thumbOut(), for: 0.3)
        #expect(d.feed(0.3) { p in HandFixture.thumbOut(offset: Point2D(x: p * 0.2, y: 0)) }.gestures == [.thumbFlickRight])
        d.hold(HandFixture.peace(), for: 0.3)
        #expect(d.feed(0.3) { p in HandFixture.peace(offset: Point2D(x: -p * 0.2, y: 0)) }.gestures == [.peaceFlickLeft])
    }

    @Test("Disabled gestures never fire")
    func disabledGesture() {
        var settings = PalmoSettings.default
        settings.enabledGestures.remove(.swipeLeft)
        var d = RecognizerDriver(settings: settings)
        d.arm()
        #expect(d.feed(0.3) { p in HandFixture.openPalm(offset: Point2D(x: -p * 0.3, y: 0)) }.gestures.isEmpty)
    }

    @Test("Thumbs-up fires once per hold thanks to its cooldown")
    func thumbsUp() {
        var d = RecognizerDriver()
        d.arm()
        let events = d.hold(HandFixture.thumbsUp(), for: 1.2)
        #expect(events.gestures == [.thumbsUp])
    }

    @Test("Palm flip (smart gesture) needs a quick over-and-back turn")
    func palmFlip() {
        var d = RecognizerDriver()
        d.arm()
        var events = d.hold(HandFixture.openPalm(flipped: true), for: 0.2)
        events += d.hold(HandFixture.openPalm(), for: 0.2)
        #expect(events.gestures == [.palmFlip])
    }

    @Test("A slow single turn is not a palm flip")
    func slowTurnIsNotFlip() {
        var d = RecognizerDriver()
        d.arm()
        let events = d.hold(HandFixture.openPalm(flipped: true), for: 1.0)
        #expect(events.gestures.isEmpty)
    }

    @Test("Confident Core ML predictions are accepted; weak ones are not")
    func motionPredictions() {
        var d = RecognizerDriver()
        d.arm()
        d.context.motionPrediction = MotionPrediction(gesture: .swipeRight, confidence: 0.5)
        #expect(d.hold(HandFixture.fist(), for: 0.1).gestures.isEmpty)
        d.context.motionPrediction = MotionPrediction(gesture: .swipeRight, confidence: 0.95)
        #expect(d.hold(HandFixture.fist(), for: 0.04).gestures == [.swipeRight])
    }

    @Test("No gestures while disarmed")
    func disarmedIsSilent() {
        var d = RecognizerDriver()
        d.hold(HandFixture.thumbsUp(), for: 1.5)
        let events = d.feed(0.3) { p in HandFixture.pointing(offset: Point2D(x: p * 0.1, y: 0)) }
        #expect(events.isEmpty)
    }
}
