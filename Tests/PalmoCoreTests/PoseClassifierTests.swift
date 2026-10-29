import Testing
@testable import PalmoCore

@Suite("Pose classifier")
struct PoseClassifierTests {
    let classifier = PoseClassifier()

    @Test("Recognizes every static shape", arguments: [
        (HandFixture.openPalm(), HandShape.openPalm),
        (HandFixture.fist(), .fist),
        (HandFixture.pointing(), .pointing),
        (HandFixture.pinch(), .indexPinch),
        (HandFixture.middlePinch(), .middlePinch),
        (HandFixture.twoFingers(), .twoFingers),
        (HandFixture.peace(), .peace),
        (HandFixture.threeFingers(), .threeFingers),
        (HandFixture.thumbOut(), .thumbOut),
        (HandFixture.thumbsUp(), .thumbsUp),
        (HandFixture.dial(), .dial),
    ])
    func shapes(pose: HandPose, expected: HandShape) {
        #expect(classifier.classify(pose) == expected)
    }

    @Test("Classification is invariant to translation, scale and mirroring")
    func invariance() {
        let shapes: [(Double, Point2D, Bool)] = [(0.6, Point2D(x: 0.2, y: 0.1), false), (1.8, Point2D(x: -0.2, y: 0), true)]
        for (scale, offset, flipped) in shapes {
            let palm = HandFixture.pose(index: .extended, middle: .extended, ring: .extended, little: .extended, thumb: .out,
                                        offset: offset, scale: scale, flipped: flipped)
            let point = HandFixture.pose(index: .extended, middle: .curled, ring: .curled, little: .curled, thumb: .tucked,
                                         offset: offset, scale: scale, flipped: flipped)
            #expect(classifier.classify(palm) == .openPalm)
            #expect(classifier.classify(point) == .pointing)
        }
    }

    @Test("Low-confidence poses are unknown")
    func lowConfidence() {
        let pose = HandFixture.pose(index: .extended, middle: .extended, ring: .extended, little: .extended,
                                    thumb: .out, confidence: 0.2)
        #expect(classifier.classify(pose) == .unknown)
    }

    @Test("Pinch has hysteresis between enter and exit gaps")
    func pinchHysteresis() {
        let hovering = HandFixture.pose(index: .extended, middle: .curled, ring: .curled, little: .curled, thumb: .nearIndex(gap: 0.3))
        #expect(classifier.classify(hovering, previous: .pointing) != .indexPinch)
        #expect(classifier.classify(hovering, previous: .indexPinch) == .indexPinch)
        let apart = HandFixture.pose(index: .extended, middle: .curled, ring: .curled, little: .curled, thumb: .nearIndex(gap: 0.5))
        #expect(classifier.classify(apart, previous: .indexPinch) != .indexPinch)
    }

    @Test("Higher sensitivity widens the pinch threshold")
    func sensitivityScaling() {
        let hovering = HandFixture.pose(index: .extended, middle: .curled, ring: .curled, little: .curled, thumb: .nearIndex(gap: 0.3))
        #expect(PoseClassifier(thresholds: .scaled(by: 1.0)).classify(hovering) != .indexPinch)
        #expect(PoseClassifier(thresholds: .scaled(by: 1.5)).classify(hovering) == .indexPinch)
    }

    @Test("Palm side flips when the hand turns over")
    func palmSide() {
        #expect(PoseMetrics(HandFixture.openPalm()).palmSide != PoseMetrics(HandFixture.openPalm(flipped: true)).palmSide)
    }
}
