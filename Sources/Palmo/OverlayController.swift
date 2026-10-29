import AppKit
import PalmoCore
import SwiftUI

/// Observable state rendered by the overlay.
@MainActor
@Observable
final class OverlayState {
    var status = EngineStatus()
}

/// A small click-through, non-activating panel in the bottom-right corner showing armed state and the hand.
@MainActor
final class OverlayController {
    weak var model: AppModel?
    private let state = OverlayState()
    private var panel: NSPanel?

    /// Shows or hides the overlay.
    func setVisible(_ visible: Bool) {
        if visible {
            if panel == nil { panel = makePanel() }
            position()
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    /// Pushes a new status snapshot.
    func update(_ status: EngineStatus) {
        guard panel?.isVisible == true else { return }
        state.status = status
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
                            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: OverlayView(state: state))
        return panel
    }

    private func position() {
        guard let panel, let screen = NSScreen.main?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: screen.maxX - panel.frame.width - 16, y: screen.minY + 16))
    }
}

/// Overlay content: status pill and a live hand skeleton.
struct OverlayView: View {
    let state: OverlayState

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if state.status.airWriting.isActive {
                AirInkView(air: state.status.airWriting)
            }
            HandSkeleton(pose: state.status.pose, armed: state.status.isArmed)
                .frame(width: 110, height: 90)
            HStack(spacing: 6) {
                if !state.status.isArmed && state.status.armProgress > 0 {
                    ZStack {
                        Circle().stroke(Color.gray.opacity(0.3), lineWidth: 2.5)
                        Circle().trim(from: 0, to: state.status.armProgress)
                            .stroke(Color.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.1), value: state.status.armProgress)
                    }
                    .frame(width: 12, height: 12)
                } else {
                    Circle().fill(state.status.isArmed ? Color.green : Color.gray).frame(width: 8, height: 8)
                }
                Text(caption).font(.caption.weight(.medium)).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.regularMaterial, in: .capsule)
        }
        .frame(width: 380, height: 260, alignment: .bottomTrailing)
    }

    private var caption: String {
        let air = state.status.airWriting
        if air.isActive {
            if air.pendingWords > 0 { return "Reading…" }
            return air.penDown ? "Writing" : "Air writing · pinch to write"
        }
        if air.templeProgress > 0 { return "Hold at temple to write…" }
        if let outcome = state.status.lastOutcome, state.status.isArmed { return OutcomeText.describe(outcome) }
        if state.status.isArmed { return "Armed" }
        if state.status.armProgress > 0 { return "Arming… keep holding ✋" }
        if state.status.handVisible, let reason = state.status.armRejection { return "Hold ✋ to arm · \(reason.explanation)" }
        return state.status.handVisible ? "Hold ✋ to arm" : "Palmo"
    }
}

/// Draws the 21 tracked joints and bones.
struct HandSkeleton: View {
    let pose: HandPose?
    let armed: Bool

    private static let chains: [[Joint]] = Finger.allCases.map { finger in
        [.wrist, finger.mcp, finger.pip, finger.dip, finger.tip]
    }

    var body: some View {
        Canvas { context, size in
            guard let pose else { return }
            let xs = pose.landmarks.map(\.location.x), ys = pose.landmarks.map(\.location.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return }
            let span = max(maxX - minX, maxY - minY, 0.001)
            func point(_ joint: Joint) -> CGPoint {
                let p: Point2D = pose[joint]
                let scale: Double = (size.height - 8) / span
                let x: Double = (p.x - minX) * scale + 4
                let y: Double = size.height - ((p.y - minY) * scale + 4)
                return CGPoint(x: x, y: y)
            }
            let color: Color = armed ? .green : .white
            for chain in Self.chains {
                var path = Path()
                path.move(to: point(chain[0]))
                for joint in chain.dropFirst() { path.addLine(to: point(joint)) }
                context.stroke(path, with: .color(color.opacity(0.85)), lineWidth: 2)
            }
            for joint in Joint.allCases {
                let p = point(joint)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)), with: .color(color))
            }
        }
        .background(.black.opacity(0.35), in: .rect(cornerRadius: 10))
        .opacity(pose == nil ? 0 : 1)
    }
}


/// Air-writing ink: the word being written, the pen, and the recognized preview.
struct AirInkView: View {
    let air: AirWritingStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Canvas { context, size in
                // Camera space (0...1, y up) mapped onto the canvas so the ink follows the hand.
                func map(_ p: Point2D) -> CGPoint { CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height) }
                var path = Path()
                for stroke in air.ink where !stroke.isEmpty {
                    path.move(to: map(stroke[0]))
                    if stroke.count == 1 { path.addLine(to: map(stroke[0]).applying(.init(translationX: 1, y: 0))) }
                    for p in stroke.dropFirst() { path.addLine(to: map(p)) }
                }
                context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                if let pen = air.penPoint {
                    let c = map(pen)
                    context.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)),
                                 with: .color(air.penDown ? .green : .gray))
                }
            }
            .frame(width: 360, height: 150)
            .background(Color.black.opacity(0.55), in: .rect(cornerRadius: 12))
            Text(air.preview.isEmpty ? "Pinch to write · 👍 type · ✌️ delete · ✊ cancel" : "“\(air.preview)”  👍 to type")
                .font(.callout.weight(.medium)).lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(.regularMaterial, in: .capsule)
        }
    }
}
