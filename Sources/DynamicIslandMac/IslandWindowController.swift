import AppKit
import SwiftUI
import Combine
import IslandGeometry

/// The panel is deliberately larger than the island so the shape can grow
/// without the window resizing. That means most of it is empty space, which
/// must stay transparent to the mouse, and clicks on the island itself must
/// work while the panel stays non-key so focus is never stolen.
private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    /// Island rect in this view's coordinate space; anything outside is see-through.
    var islandRect: (() -> CGRect)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let islandRect, islandRect().contains(point) else { return nil }
        return super.hitTest(point)
    }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        makeLayerTransparent()
    }

    /// `NSHostingView`'s backing `CALayer` defaults to opaque even inside a
    /// window explicitly marked `isOpaque = false`. An opaque layer tells the
    /// compositor it can skip alpha blending and paint the *entire* layer
    /// bounds solid — which for this 333×205 fixed-size container means the
    /// whole box shows filled black on screen, regardless of how small the
    /// clipped shape SwiftUI actually draws inside it. This only shows up in
    /// real on-screen compositing, not in a captured image of the view's own
    /// backing buffer, which is what made it look fine in every offline check.
    private func makeLayerTransparent() {
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class IslandWindowController: NSWindowController {
    private let model: IslandViewModel
    private let settings = IslandSettings.shared
    private var cancellables = Set<AnyCancellable>()

    init(model: IslandViewModel) {
        self.model = model
        let settings = IslandSettings.shared
        let panel = IslandPanel(
            contentRect: NSRect(origin: .zero, size: settings.containerSize(notch: model.notchSize, hasNotch: model.hasNotch))
        )
        super.init(window: panel)

        let hosting = ClickThroughHostingView(
            rootView: IslandView(model: model, settings: settings)
        )
        hosting.islandRect = { [weak self] in
            guard let self, let panel = self.window else { return .zero }
            return self.islandRectInWindow(panel: panel)
        }
        panel.contentView = hosting

        model.pointerIsInsideIsland = { [weak self] in
            guard let self, let panel = self.window else { return false }
            let local = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
            return self.islandRectInWindow(panel: panel).contains(local)
        }

        positionContainer()
        panel.orderFrontRegardless()

        // Settings edits should be reflected without waiting for a state change.
        // Delivering on the main run loop lets the published value settle first.
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.window?.hasShadow = self.settings.showShadow
                self.positionContainer()
            }
            .store(in: &cancellables)

        // Plugging a monitor in or out, closing the lid, changing the main
        // display or resolution all land here; re-place and re-measure.
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                // Re-measure first; the settings sink above then re-places the panel.
                self.refreshNotch()
                self.settings.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Fixed frame pinned to the top-center of the display; only the SwiftUI
    /// shape inside changes size.
    private func positionContainer() {
        guard let panel = window else { return }
        guard let screen = IslandDisplay.screen else { return }
        refreshNotch(for: screen)
        let size = settings.containerSize(notch: model.notchSize, hasNotch: model.hasNotch)
        let origin = DisplayGeometry.panelOrigin(containerSize: size, on: IslandDisplay.info(for: screen))
        let frame = NSRect(origin: origin, size: size)
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: true)
    }

    /// Updates the cached notch only when it changed, to avoid needless redraws.
    private func refreshNotch(for screen: NSScreen? = IslandDisplay.screen) {
        let notch = ScreenNotch.size(for: screen)
        let hasNotch = ScreenNotch.hasNotch(for: screen)
        if model.notchSize != notch { model.notchSize = notch }
        if model.hasNotch != hasNotch { model.hasNotch = hasNotch }
    }

    /// The island hugs the top edge and is centred horizontally. Window
    /// coordinates put the origin at the bottom-left, so it sits at the top.
    private func islandRectInWindow(panel: NSWindow) -> CGRect {
        let container = panel.frame.size
        let island = model.islandSize(settings: settings, notch: model.notchSize)
        return CGRect(
            x: (container.width - island.width) / 2,
            y: container.height - island.height,
            width: island.width,
            height: island.height
        )
    }

}

#if DEBUG
extension IslandWindowController {
    /// The island's current shape in screen coordinates, for the debug server.
    var debugIslandScreenRect: CGRect? {
        guard let panel = window else { return nil }
        return panel.convertToScreen(islandRectInWindow(panel: panel))
    }
}
#endif
