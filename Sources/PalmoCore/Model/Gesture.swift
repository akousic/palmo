import Foundation

/// Every gesture Palmo recognizes.
public enum Gesture: String, CaseIterable, Sendable, Codable, CodingKeyRepresentable, Identifiable {
    case arm, disarm
    case point, pinchClick, pinchDrag, middlePinch, twoFingerScroll, volumeDial
    case swipeLeft, swipeRight
    case threeFingerUp, threeFingerDown
    case thumbFlickLeft, thumbFlickRight
    case thumbsUp
    case peaceFlickLeft, peaceFlickRight
    case palmFlip

    /// Stable identifier for SwiftUI lists.
    public var id: String { rawValue }

    /// Short human-readable name.
    public var title: String {
        switch self {
        case .arm: "Arm (open palm hold)"
        case .disarm: "Disarm (fist hold)"
        case .point: "Point & move"
        case .pinchClick: "Pinch click"
        case .pinchDrag: "Pinch hold & drag"
        case .middlePinch: "Middle pinch"
        case .twoFingerScroll: "Two-finger scroll"
        case .volumeDial: "Volume dial"
        case .swipeLeft: "Open-hand swipe left"
        case .swipeRight: "Open-hand swipe right"
        case .threeFingerUp: "Three-finger flick up"
        case .threeFingerDown: "Three-finger flick down"
        case .thumbFlickLeft: "Thumb flick left"
        case .thumbFlickRight: "Thumb flick right"
        case .thumbsUp: "Thumbs up"
        case .peaceFlickLeft: "Peace flick left"
        case .peaceFlickRight: "Peace flick right"
        case .palmFlip: "Palm flip (smart)"
        }
    }

    /// Emoji used in menus, the overlay and docs.
    public var emoji: String {
        switch self {
        case .arm: "✋"
        case .disarm: "✊"
        case .point: "☝️"
        case .pinchClick: "🤏"
        case .pinchDrag: "🤏➡️"
        case .middlePinch: "🤌"
        case .twoFingerScroll: "✌️↕️"
        case .volumeDial: "🤏🔄"
        case .swipeLeft: "👋⬅️"
        case .swipeRight: "👋➡️"
        case .threeFingerUp: "🤟⬆️"
        case .threeFingerDown: "🤟⬇️"
        case .thumbFlickLeft: "👍⬅️"
        case .thumbFlickRight: "👍➡️"
        case .thumbsUp: "👍"
        case .peaceFlickLeft: "✌️👈"
        case .peaceFlickRight: "✌️👉"
        case .palmFlip: "🖐️🔁"
        }
    }

    /// Whether the gesture drives the low-latency fast path (never routed through the language model).
    public var isFastPath: Bool {
        switch self {
        case .point, .pinchClick, .pinchDrag, .middlePinch, .twoFingerScroll, .volumeDial: true
        default: false
        }
    }

    /// Whether users may rebind the gesture to another action.
    public var isRebindable: Bool {
        !isFastPath && self != .arm && self != .disarm
    }

    /// All gestures users may rebind.
    public static var rebindable: [Gesture] { allCases.filter(\.isRebindable) }

    /// Raw names of rebindable gestures (used to constrain guided generation).
    public static var rebindableNames: [String] { rebindable.map(\.rawValue) }
}
