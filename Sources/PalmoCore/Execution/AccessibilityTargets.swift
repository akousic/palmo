import ApplicationServices
import Foundation

/// Accessibility hit-testing and window-button presses. All calls use a short messaging timeout so
/// an unresponsive app can never stall the pointer.
enum AccessibilityTargets {
    static let clickableRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXLink",
        "AXMenuItem", "AXMenuBarItem", "AXDisclosureTriangle", "AXTab", "AXSegment", "AXDockItem",
    ]
    static let windowButtonSubroles: Set<String> = [
        "AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton",
    ]
    /// Larger than a typical control's snap radius: traffic-light buttons are only ~14 pt wide.
    static let windowButtonBonus = 1.5

    /// Finds the clickable control at or nearest to `point` within `radius` points.
    static func clickableFrame(near point: ScreenPoint, radius: Double) -> ScreenRect? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.05)
        var probes: [(Double, Double)] = [(0, 0)]
        let maxRadius = radius * windowButtonBonus
        for ring in [maxRadius / 3, maxRadius * 2 / 3, maxRadius] {
            for k in 0..<8 {
                let a = Double(k) * .pi / 4
                probes.append((cos(a) * ring, sin(a) * ring))
            }
        }
        var best: (frame: ScreenRect, distance: Double)?
        var seen: [ScreenRect] = []
        for (dx, dy) in probes {
            guard let (frame, isWindowButton) = clickable(at: point.x + dx, point.y + dy, system: system),
                  !seen.contains(frame) else { continue }
            seen.append(frame)
            let distance = distanceFrom(point, to: frame)
            let limit = isWindowButton ? maxRadius : radius
            guard distance <= limit else { continue }
            if distance == 0 { return frame }
            if best == nil || distance < best!.distance { best = (frame, distance) }
        }
        return best?.frame
    }

    /// Presses the focused window's close or minimize button. Returns false if it couldn't.
    static func pressFocusedWindowButton(_ attribute: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        guard let app = element(system, kAXFocusedApplicationAttribute),
              let window = element(app, kAXFocusedWindowAttribute),
              let button = element(window, attribute) else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    // MARK: - Private

    private static func clickable(at x: Double, _ y: Double, system: AXUIElement) -> (ScreenRect, Bool)? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(x), Float(y), &hit) == .success, var current = hit else { return nil }
        for _ in 0..<3 {
            let role = string(current, kAXRoleAttribute) ?? ""
            let subrole = string(current, kAXSubroleAttribute) ?? ""
            if clickableRoles.contains(role) || windowButtonSubroles.contains(subrole), let f = frame(current),
               f.width > 0, f.width < 600 {
                return (f, windowButtonSubroles.contains(subrole))
            }
            guard let parent = element(current, kAXParentAttribute) else { return nil }
            current = parent
        }
        return nil
    }

    private static func distanceFrom(_ p: ScreenPoint, to r: ScreenRect) -> Double {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return hypot(dx, dy)
    }

    private static func element(_ e: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func string(_ e: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func frame(_ e: AXUIElement) -> ScreenRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let posValue, let sizeValue,
              CFGetTypeID(posValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return ScreenRect(minX: origin.x, minY: origin.y, maxX: origin.x + size.width, maxY: origin.y + size.height)
    }
}
