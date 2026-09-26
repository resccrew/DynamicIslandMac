import AppKit

/// Borderless, non-activating panel pinned under the notch. Floats above
/// everything and never steals focus or shows up in the Dock/Cmd-Tab
/// switcher. Over fullscreen Spaces only when `hideInFullScreen` is off.
final class IslandPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = IslandSettings.shared.showShadow
        level = .statusBar
        applySpaceBehavior(hideInFullScreen: IslandSettings.shared.hideInFullScreen)
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    /// Without `.fullScreenAuxiliary` the window server keeps the panel off
    /// fullscreen Spaces by itself — the first line of defence; the window
    /// controller's fullscreen check covers what that misses.
    func applySpaceBehavior(hideInFullScreen: Bool) {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if !hideInFullScreen { behavior.insert(.fullScreenAuxiliary) }
        if collectionBehavior != behavior { collectionBehavior = behavior }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
