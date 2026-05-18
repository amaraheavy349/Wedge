import AppKit
import SwiftUI

/// Borderless transparent panel that sits over the screen and renders the
/// wedge being dragged out of the status item.
@MainActor
final class WedgePanel: NSPanel {
    private let anchorOnScreen: CGPoint
    private let hostingView: NSHostingView<WedgeView>
    private var tipOnScreen: CGPoint
    private var isOn: Bool
    private var armProgress: Double = 0

    init(anchorOnScreen: CGPoint, isOn: Bool) {
        self.anchorOnScreen = anchorOnScreen
        self.tipOnScreen = anchorOnScreen
        self.isOn = isOn

        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchorOnScreen) })
            ?? NSScreen.main
            ?? NSScreen.screens.first!
        let frame = screen.frame

        self.hostingView = NSHostingView(rootView: WedgeView(anchor: .zero, tip: .zero, isOn: isOn, armProgress: 0))

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isFloatingPanel = true

        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        contentView = hostingView

        refresh()
    }

    func updateTip(_ screenPoint: CGPoint, armProgress: Double = 0) {
        tipOnScreen = screenPoint
        self.armProgress = max(0, min(1, armProgress))
        refresh()
    }

    func updateState(isOn: Bool) {
        self.isOn = isOn
        refresh()
    }

    func show() {
        orderFrontRegardless()
    }

    /// Animates the wedge back to the anchor with a soft elastic feel, then closes.
    func snapBack(completion: @escaping @MainActor () -> Void) {
        let start = tipOnScreen
        let end = anchorOnScreen
        let duration: CFTimeInterval = 0.32
        let startTime = CACurrentMediaTime()

        Task { @MainActor [weak self] in
            while true {
                let raw = (CACurrentMediaTime() - startTime) / duration
                let t = min(1.0, raw)
                let eased = Self.easeOutBack(t)
                let x = start.x + (end.x - start.x) * eased
                let y = start.y + (end.y - start.y) * eased
                self?.updateTip(CGPoint(x: x, y: y))
                if t >= 1.0 { break }
                try? await Task.sleep(nanoseconds: 8_000_000) // ~120 fps
            }
            self?.orderOut(nil)
            completion()
        }
    }

    private func refresh() {
        let f = frame
        // Convert screen (bottom-left origin) -> SwiftUI local (top-left origin)
        let anchorLocal = CGPoint(
            x: anchorOnScreen.x - f.origin.x,
            y: f.height - (anchorOnScreen.y - f.origin.y)
        )
        let tipLocal = CGPoint(
            x: tipOnScreen.x - f.origin.x,
            y: f.height - (tipOnScreen.y - f.origin.y)
        )
        hostingView.rootView = WedgeView(
            anchor: anchorLocal,
            tip: tipLocal,
            isOn: isOn,
            armProgress: armProgress
        )
    }

    private static func easeOutBack(_ t: Double) -> Double {
        let c1 = 1.70158
        let c3 = c1 + 1
        let x = t - 1
        return 1 + c3 * x * x * x + c1 * x * x
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
