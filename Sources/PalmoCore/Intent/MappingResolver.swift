import Foundation

/// The outcome of looking up what a discrete gesture should do.
public enum MappingResolution: Sendable, Equatable {
    /// Execute this concrete action.
    case action(PalmoAction)
    /// Ask the context resolver (Foundation Models, falling back to rules).
    case contextual
    /// Do nothing.
    case ignore
}

/// Pure lookup of gesture → action, honouring per-app overrides.
public enum MappingResolver {
    /// Resolves a discrete gesture for the given frontmost app.
    ///
    /// Order: disabled gesture → ignore; per-app override; global mapping; nothing.
    public static func resolve(_ gesture: Gesture, app: AppContext, settings: PalmoSettings) -> MappingResolution {
        guard settings.isEnabled(gesture), gesture.isRebindable else { return .ignore }
        let action = settings.appOverrides[app.bundleID]?[gesture] ?? settings.mappings[gesture]
        switch action {
        case .none?, nil: return .ignore
        case .contextual?: return .contextual
        case let concrete?: return .action(concrete)
        }
    }
}
