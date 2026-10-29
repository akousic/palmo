import Foundation
import Synchronization

/// A point in global display coordinates (points, origin at the top-left of the main display).
public struct ScreenPoint: Sendable, Hashable {
    /// Horizontal coordinate.
    public var x: Double
    /// Vertical coordinate.
    public var y: Double

    /// Creates a point.
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Everything the intent layer needs from the operating system. Abstracted so routing is unit-testable.
public protocol InputSynthesizing: Sendable {
    /// Current cursor location.
    func cursorPosition() async -> ScreenPoint
    /// Union of all active displays.
    func screenBounds() async -> ScreenRect
    /// Moves the cursor; `dragging` posts drag events instead of move events.
    func moveCursor(to point: ScreenPoint, dragging: Bool) async
    /// Left click at the cursor; `count` 2 = double-click.
    func click(count: Int) async
    /// Right click at the cursor.
    func rightClick() async
    /// Presses the left button.
    func mouseDown() async
    /// Releases the left button.
    func mouseUp() async
    /// Scrolls by pixel deltas (positive y = scroll content down, i.e. reveal earlier content).
    func scroll(dx: Int, dy: Int) async
    /// Changes volume by `steps` detents.
    func volume(steps: Int) async
    /// Executes a high-level action in the context of `app`.
    func perform(_ action: PalmoAction, app: AppContext) async throws
    /// Frame of the clickable control (button, checkbox, link, window close/minimize/zoom button…)
    /// at or within `radius` points of `point`, if any. Used to snap clicks onto small targets.
    func clickableFrame(near point: ScreenPoint, radius: Double) async -> ScreenRect?
    /// Types text into the focused field.
    func typeText(_ text: String) async
}

extension InputSynthesizing {
    /// Default: no target snapping.
    public func clickableFrame(near point: ScreenPoint, radius: Double) async -> ScreenRect? { nil }
    /// Default: no typing.
    public func typeText(_ text: String) async {}
}

/// Thread-safe one-shot continuation resumer used to race work against a timeout.
final class OnceResumer<T: Sendable>: Sendable {
    private let continuation: Mutex<CheckedContinuation<T, Never>?>

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = Mutex(continuation)
    }

    func resume(_ value: T) {
        let c = continuation.withLock { stored -> CheckedContinuation<T, Never>? in
            defer { stored = nil }
            return stored
        }
        c?.resume(returning: value)
    }
}

/// Runs `operation` and returns its result, or `nil` if it takes longer than `seconds`.
///
/// Unlike a task group, this returns as soon as the timeout fires even if the operation ignores cancellation.
public func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async -> T?) async -> T? {
    await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
        let once = OnceResumer(continuation)
        let work = Task {
            let value = await operation()
            once.resume(value)
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            work.cancel()
            once.resume(nil)
        }
    }
}
