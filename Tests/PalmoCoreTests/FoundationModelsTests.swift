import Testing
@testable import PalmoCore

/// Exercises the real on-device model. Skipped automatically when Apple Intelligence is unavailable.
@Suite("Foundation Models (on-device)", .enabled(if: FoundationModelsContextResolver.isModelAvailable), .serialized)
struct FoundationModelsTests {
    @Test("Smart gesture in Keynote resolves to a valid candidate action", .timeLimit(.minutes(1)))
    func keynote() async throws {
        let action = try await FoundationModelsContextResolver()
            .resolve(gesture: .palmFlip, app: AppContext(bundleID: "com.apple.iWork.Keynote", name: "Keynote"))
        if let action { #expect(FoundationModelsContextResolver.candidates.contains(action)) }
    }

    @Test("Natural-language configuration produces a mapping change", .timeLimit(.minutes(1)))
    func configure() async throws {
        let result = await MappingConfigurator(useAppleIntelligence: true).interpret("make thumbs up mute the volume")
        let proposal = try #require(result)
        #expect(proposal.change.gesture == .thumbsUp)
    }
}
