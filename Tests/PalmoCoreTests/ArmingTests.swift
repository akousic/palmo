import Foundation
import Testing
@testable import PalmoCore

@Suite("Arming reliability")
struct ArmingTests {
    @Test("Single dropped frames do not reset the arm hold")
    func dropoutsTolerated() {
        var d = RecognizerDriver()
        let palm = HandFixture.openPalm()
        var frame = 0
        d.feed(1.2) { _ in frame += 1; return frame % 4 == 0 ? nil : palm }
        #expect(d.recognizer.isArmed)
    }

    @Test("Interleaved misclassified frames do not reset the arm hold")
    func misclassifiedFramesTolerated() {
        var d = RecognizerDriver()
        var frame = 0
        d.feed(1.2) { _ in frame += 1; return frame % 3 == 0 ? HandFixture.pointing() : HandFixture.openPalm() }
        #expect(d.recognizer.isArmed)
    }

    @Test("A long gap resets the hold")
    func longGapResets() {
        var d = RecognizerDriver()
        d.hold(HandFixture.openPalm(), for: 0.5)
        d.hold(nil, for: 0.6)
        d.hold(HandFixture.openPalm(), for: 0.4)
        #expect(!d.recognizer.isArmed)
        d.hold(HandFixture.openPalm(), for: 0.5)
        #expect(d.recognizer.isArmed)
    }

    @Test("A relaxed palm (less fanned, thumb part-way) still arms")
    func relaxedPalmArms() {
        var d = RecognizerDriver()
        let relaxed = HandFixture.pose(index: .extended, middle: .extended, ring: .extended, little: .extended,
                                       thumb: .nearIndex(gap: 0.6), tipSpread: 0.35, confidence: 0.5)
        #expect(ArmPalmTest().evaluate(relaxed) == nil)
        d.hold(relaxed, for: 1.0)
        #expect(d.recognizer.isArmed)
    }

    @Test("Fist, pointing and thumbs-up never arm", arguments: [HandFixture.fist(), HandFixture.pointing(), HandFixture.thumbsUp()])
    func nonPalmsDoNotArm(_ pose: HandPose) {
        var d = RecognizerDriver()
        d.hold(pose, for: 2.0)
        #expect(!d.recognizer.isArmed)
        #expect(d.recognizer.lastArmRejection != nil)
    }

    @Test("Typing blocks arming and reports why")
    func typingReason() {
        var d = RecognizerDriver()
        d.context.secondsSinceKeyboardInput = 0.1
        d.hold(HandFixture.openPalm(), for: 1.5)
        #expect(!d.recognizer.isArmed)
        #expect(d.recognizer.lastArmRejection == .typing)
    }

    @Test("Arm progress events build up to arming")
    func progressEvents() {
        var d = RecognizerDriver()
        let events = d.hold(HandFixture.openPalm(), for: 1.0)
        let progress = events.compactMap { if case .armProgress(let p) = $0 { p } else { nil } }
        #expect(progress.count >= 3)
        #expect(progress.last == 1)
        #expect(zip(progress, progress.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test("Accumulator needs a minimum number of frames")
    func minFrames() {
        var acc = ArmAccumulator(); var r = false
        #expect(!acc.update(qualifies: true, at: 0, restarted: &r))
        #expect(!acc.update(qualifies: true, at: 0.35, restarted: &r))
        #expect(!acc.update(qualifies: true, at: 0.7, restarted: &r))
        #expect(acc.frames < acc.minFrames || acc.held < acc.dwell)
    }

    @Test("Higher sensitivity is more forgiving")
    func sensitivityScales() {
        let easy = ArmPalmTest.scaled(by: 1.5), strict = ArmPalmTest.scaled(by: 0.5)
        #expect(easy.fan < ArmPalmTest().fan && strict.fan > ArmPalmTest().fan)
        #expect(easy.extended < strict.extended)
    }

    @Test("Old settings decode with the default arm sensitivity")
    func settingsDefault() throws {
        let data = try JSONEncoder().encode(PalmoSettings.default)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "armSensitivity")
        let decoded = try JSONDecoder().decode(PalmoSettings.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.armSensitivity == 1.0)
    }
}
