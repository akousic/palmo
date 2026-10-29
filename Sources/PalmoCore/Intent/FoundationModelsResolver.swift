import Foundation
import FoundationModels
import Synchronization

/// Arguments the model supplies when it calls an action tool.
@Generable
public struct ActionToolArguments: Sendable {
    /// Why the model picked this action.
    @Guide(description: "One short sentence explaining why this action fits the frontmost app.")
    public var reason: String
}

/// Thread-safe record of which action tools the model invoked during one response.
public final class ActionChoiceRecorder: Sendable {
    private let chosen = Mutex<[PalmoAction]>([])

    /// Creates an empty recorder.
    public init() {}

    /// Records a choice. Returns `true` if it is the first one (only the first is honoured).
    public func record(_ action: PalmoAction) -> Bool {
        chosen.withLock { list in
            list.append(action)
            return list.count == 1
        }
    }

    /// The first recorded choice.
    public var first: PalmoAction? { chosen.withLock { $0.first } }
}

/// A Foundation Models tool representing one executable `PalmoAction`.
///
/// The model selects an action by calling its tool. The tool records the choice and the
/// `IntentRouter` executes it, which guarantees exactly-once execution, validation and
/// a hard timeout independent of the model.
public struct ActionTool: Tool {
    /// The action this tool represents.
    public let action: PalmoAction
    private let recorder: ActionChoiceRecorder

    /// Creates a tool for `action` that reports to `recorder`.
    public init(action: PalmoAction, recorder: ActionChoiceRecorder) {
        self.action = action
        self.recorder = recorder
    }

    /// Tool name (the action's raw value).
    public var name: String { action.rawValue }
    /// Tool description shown to the model.
    public var description: String { action.toolDescription }

    /// Records the selection and acknowledges it to the model.
    public func call(arguments: ActionToolArguments) async throws -> String {
        recorder.record(action)
            ? "Done: \(action.title). Do not call any other tool."
            : "An action was already chosen. Do not call any other tool."
    }
}

/// Guided-generation output for context resolution, used when the model answers without calling a tool.
@Generable
public struct ActionResolution: Sendable {
    /// The chosen action's raw value.
    @Guide(description: "The single most useful action for the frontmost app.",
           .anyOf(FoundationModelsContextResolver.candidateNames))
    public var action: String
    /// Short justification.
    @Guide(description: "One short sentence explaining the choice.")
    public var reason: String
}

/// Resolves the smart gesture with the on-device Apple Intelligence model, using tool calling and guided generation.
public actor FoundationModelsContextResolver: ContextResolver {
    /// Actions offered to the model for the smart gesture (kept small for the context window and safety).
    public static let candidates: [PalmoAction] = [
        .browserReload, .browserBack, .browserForward, .newTab,
        .nextSlide, .previousSlide, .startSlideshow,
        .playPause, .nextTrack,
        .quickLook, .runBuild, .toggleMeetingMute, .toggleFullScreen,
        .missionControl, .escape,
    ]

    /// Raw names of `candidates`.
    public static let candidateNames: [String] = candidates.map(\.rawValue)

    /// Whether the system model can be used right now.
    public static var isModelAvailable: Bool { SystemLanguageModel.default.isAvailable }

    /// A human-readable explanation of the model's availability.
    public static var availabilityDescription: String {
        switch SystemLanguageModel.default.availability {
        case .available: "Apple Intelligence is available."
        case .unavailable(.deviceNotEligible): "This Mac does not support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): "Apple Intelligence is turned off in System Settings."
        case .unavailable(.modelNotReady): "The Apple Intelligence model is still downloading."
        case .unavailable: "Apple Intelligence is unavailable."
        }
    }

    private static let instructions = """
        You map a hand gesture to one Mac action. The user made the "palm flip" gesture, which means \
        "do the obvious thing here". Pick the single most useful action for the frontmost app by calling \
        exactly one tool. Prefer: browsers → reload; presentation apps → next slide; music apps → next track; \
        video players → play/pause; Xcode → run; video calls → toggle meeting mute; Finder → Quick Look. \
        Never pick an action that could lose data.
        """

    private var prepared: (session: LanguageModelSession, recorder: ActionChoiceRecorder)?

    /// Creates the resolver.
    public init() {}

    private func makeSession() -> (session: LanguageModelSession, recorder: ActionChoiceRecorder) {
        let recorder = ActionChoiceRecorder()
        let tools: [any Tool] = Self.candidates.map { ActionTool(action: $0, recorder: recorder) }
        let session = LanguageModelSession(tools: tools, instructions: Self.instructions)
        return (session, recorder)
    }

    /// Loads the model and a fresh session ahead of time so the next resolution is fast.
    public func prewarm() {
        guard Self.isModelAvailable else { return }
        let pair = prepared ?? makeSession()
        pair.session.prewarm()
        prepared = pair
    }

    /// Asks the model which action fits `app`. Each call uses a fresh session so context never accumulates.
    public func resolve(gesture: Gesture, app: AppContext) async throws -> PalmoAction? {
        guard Self.isModelAvailable else { return nil }
        let pair = prepared ?? makeSession()
        prepared = nil
        defer { prewarmNext() }
        let prompt = "Frontmost app: \(app.name) (bundle identifier \(app.bundleID)). Gesture: \(gesture.title)."
        let response = try await pair.session.respond(to: prompt, generating: ActionResolution.self)
        if let chosen = pair.recorder.first { return chosen }
        return PalmoAction(rawValue: response.content.action).flatMap { Self.candidates.contains($0) ? $0 : nil }
    }

    private func prewarmNext() {
        let pair = makeSession()
        pair.session.prewarm()
        prepared = pair
    }
}
