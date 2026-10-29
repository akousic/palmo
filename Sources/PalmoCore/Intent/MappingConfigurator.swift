import Foundation
import FoundationModels

/// A proposed change to the gesture mapping, produced from natural language.
public struct MappingChange: Sendable, Hashable {
    /// The gesture to rebind.
    public var gesture: Gesture
    /// The new action.
    public var action: PalmoAction
    /// App the change is scoped to (display name), or `nil` for a global change.
    public var appName: String?

    /// Creates a change.
    public init(gesture: Gesture, action: PalmoAction, appName: String? = nil) {
        self.gesture = gesture
        self.action = action
        self.appName = appName
    }

    /// A sentence describing the change for confirmation UI.
    public var summary: String {
        let scope = appName.map { " in \($0)" } ?? ""
        return "\(gesture.emoji) \(gesture.title) → \(action.title)\(scope)"
    }
}

extension PalmoSettings {
    /// Returns settings with `change` applied. A scoped change needs the app's bundle identifier.
    public func applying(_ change: MappingChange, bundleID: String?) -> PalmoSettings {
        var copy = self
        guard change.gesture.isRebindable else { return copy }
        if change.appName != nil, let bundleID, !bundleID.isEmpty {
            copy.appOverrides[bundleID, default: [:]][change.gesture] = change.action
            copy.appNames[bundleID] = change.appName
        } else {
            copy.mappings[change.gesture] = change.action
        }
        copy.enabledGestures.insert(change.gesture)
        return copy
    }
}

/// Deterministic keyword parser for mapping requests; the fallback when Apple Intelligence is unavailable.
public enum RuleBasedMappingParser {
    static let gesturePhrases: [(String, Gesture)] = [
        ("thumbs up", .thumbsUp), ("thumb up", .thumbsUp), ("👍", .thumbsUp),
        ("palm flip", .palmFlip), ("flip my palm", .palmFlip), ("flip palm", .palmFlip), ("smart gesture", .palmFlip),
        ("swipe left", .swipeLeft), ("swipe right", .swipeRight),
        ("three finger up", .threeFingerUp), ("three fingers up", .threeFingerUp),
        ("three finger flick up", .threeFingerUp), ("three finger down", .threeFingerDown),
        ("three fingers down", .threeFingerDown), ("three finger flick down", .threeFingerDown),
        ("thumb flick left", .thumbFlickLeft), ("flick thumb left", .thumbFlickLeft),
        ("thumb flick right", .thumbFlickRight), ("flick thumb right", .thumbFlickRight),
        ("peace flick left", .peaceFlickLeft), ("peace left", .peaceFlickLeft), ("peace sign left", .peaceFlickLeft),
        ("peace flick right", .peaceFlickRight), ("peace right", .peaceFlickRight), ("peace sign right", .peaceFlickRight),
    ]

    static let actionPhrases: [(String, PalmoAction)] = [
        ("mute my mic", .toggleMeetingMute), ("mute the meeting", .toggleMeetingMute), ("meeting mute", .toggleMeetingMute),
        ("mute my microphone", .toggleMeetingMute), ("microphone", .toggleMeetingMute),
        ("play pause", .playPause), ("pause", .playPause), ("play", .playPause), ("resume", .playPause),
        ("next track", .nextTrack), ("next song", .nextTrack), ("skip", .nextTrack),
        ("previous track", .previousTrack), ("previous song", .previousTrack), ("last song", .previousTrack),
        ("volume up", .volumeUp), ("louder", .volumeUp), ("volume down", .volumeDown), ("quieter", .volumeDown),
        ("unmute", .toggleMute), ("mute", .toggleMute),
        ("next space", .nextSpace), ("next desktop", .nextSpace),
        ("previous space", .previousSpace), ("previous desktop", .previousSpace),
        ("mission control", .missionControl), ("app expose", .appExpose), ("app exposé", .appExpose),
        ("all windows", .appExpose), ("show desktop", .showDesktop),
        ("next app", .appSwitcherNext), ("switch app", .appSwitcherNext), ("previous app", .appSwitcherPrevious),
        ("reload", .browserReload), ("refresh", .browserReload),
        ("go back", .browserBack), ("back", .browserBack), ("go forward", .browserForward), ("forward", .browserForward),
        ("new tab", .newTab), ("close tab", .closeTab), ("close the tab", .closeTab),
        ("next slide", .nextSlide), ("previous slide", .previousSlide),
        ("start the slideshow", .startSlideshow), ("start slideshow", .startSlideshow), ("slideshow", .startSlideshow),
        ("present", .startSlideshow),
        ("quick look", .quickLook), ("quicklook", .quickLook),
        ("run", .runBuild), ("build", .runBuild),
        ("full screen", .toggleFullScreen), ("fullscreen", .toggleFullScreen),
        ("undo", .undo), ("escape", .escape),
        ("depends on the app", .contextual), ("smart", .contextual), ("context", .contextual),
        ("do nothing", .none), ("nothing", .none), ("disable", .none),
    ]

    static func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "/", with: " ")
        return lowered.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func firstMatch<T>(in text: String, phrases: [(String, T)]) -> (T, Range<String.Index>)? {
        var best: (T, Range<String.Index>, Int)?
        for (phrase, value) in phrases {
            let escaped = NSRegularExpression.escapedPattern(for: phrase)
            guard let regex = try? NSRegularExpression(pattern: "(?<![\\p{L}])\(escaped)(?![\\p{L}])"),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range, in: text) else { continue }
            // Prefer the longest phrase; ties go to the earliest occurrence.
            if best == nil || phrase.count > best!.2 || (phrase.count == best!.2 && range.lowerBound < best!.1.lowerBound) {
                best = (value, range, phrase.count)
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    /// Extracts a capitalized app name introduced by "in", "when in", "while using", "for", etc.
    static func appName(in original: String) -> String? {
        let pattern = "(?:^|\\b)(?:[Ww]hen (?:I'?m |I am )?(?:in|using)|[Ww]hile (?:in|using)|[Ii]n|[Ff]or|[Ii]nside)\\s+((?:[A-Z0-9][\\w.&+']*)(?:\\s+[A-Z0-9][\\w.&+']*)*)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        for match in regex.matches(in: original, range: NSRange(original.startIndex..., in: original)) {
            guard let range = Range(match.range(at: 1), in: original) else { continue }
            let name = String(original[range]).trimmingCharacters(in: .punctuationCharacters)
            if !name.isEmpty { return name }
        }
        return nil
    }

    /// Parses a request like "make thumbs up pause my music" or "In Keynote, palm flip should start the slideshow".
    public static func parse(_ text: String) -> MappingChange? {
        let normalized = normalize(text)
        guard let (gesture, gestureRange) = firstMatch(in: normalized, phrases: gesturePhrases) else { return nil }
        // Search for the action outside the gesture phrase so "thumb flick" never matches "flick".
        var remainder = normalized
        remainder.replaceSubrange(gestureRange, with: String(repeating: " ", count: normalized.distance(from: gestureRange.lowerBound, to: gestureRange.upperBound)))
        guard let (action, _) = firstMatch(in: remainder, phrases: actionPhrases) else { return nil }
        return MappingChange(gesture: gesture, action: action, appName: appName(in: text))
    }
}

/// Guided-generation schema for natural-language mapping requests.
@Generable
public struct MappingProposal: Sendable {
    /// Gesture raw value.
    @Guide(description: "The gesture the user wants to change.", .anyOf(Gesture.rebindableNames))
    public var gesture: String
    /// Action raw value.
    @Guide(description: "The action the gesture should perform. Use 'contextual' when it should depend on the app.",
           .anyOf(PalmoAction.mappableNames))
    public var action: String
    /// App scope.
    @Guide(description: "The app name if the user limited the change to one app, otherwise an empty string.")
    public var appName: String
}

/// Turns natural-language requests into `MappingChange`s, using Apple Intelligence when available and rules otherwise.
public struct MappingConfigurator: Sendable {
    /// Where an interpretation came from.
    public enum Source: String, Sendable {
        case appleIntelligence
        case rules
    }

    /// Whether to try Foundation Models first.
    public var useAppleIntelligence: Bool

    /// Creates a configurator.
    public init(useAppleIntelligence: Bool) {
        self.useAppleIntelligence = useAppleIntelligence
    }

    private static let instructions = """
        You configure a hand-gesture app for the Mac. Convert the user's request into exactly one gesture \
        and one action. Gestures: \(Gesture.rebindable.map { "\($0.rawValue) (\($0.title))" }.joined(separator: ", ")). \
        Leave appName empty unless the user names a specific app.
        """

    /// Interprets `text`. Returns `nil` when neither the model nor the rules understand it.
    public func interpret(_ text: String) async -> (change: MappingChange, source: Source)? {
        if useAppleIntelligence && SystemLanguageModel.default.isAvailable {
            do {
                let session = LanguageModelSession(instructions: Self.instructions)
                let response = try await session.respond(to: text, generating: MappingProposal.self)
                let proposal = response.content
                if let gesture = Gesture(rawValue: proposal.gesture), gesture.isRebindable,
                   let action = PalmoAction(rawValue: proposal.action) {
                    let app = proposal.appName.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (MappingChange(gesture: gesture, action: action, appName: app.isEmpty ? nil : app), .appleIntelligence)
                }
            } catch {
                // Guardrail violations, context overflow or model errors: fall through to the deterministic parser.
            }
        }
        return RuleBasedMappingParser.parse(text).map { ($0, .rules) }
    }
}
