import AppKit
import SwiftUI

/// Hosts the Claude Code status pill just to the right of the island.
///
/// Its own panel, separate from the island: it has an independent visibility
/// rule (hidden whenever no Claude Code session exists at all, regardless of
/// what the island is doing) and no reason to share the island's layout logic.
final class AgentStatusWindowController: NSWindowController {
    private let monitor = ClaudeAgentMonitor()
    private var currentStatus: ClaudeAgentMonitor.Status?

    init() {
        let size = CGSize(width: 46, height: 28)
        let panel = IslandPanel(contentRect: NSRect(origin: .zero, size: size))
        super.init(window: panel)

        reposition(width: size.width)

        monitor.start { [weak self] status in
            self?.apply(status)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func apply(_ status: ClaudeAgentMonitor.Status?) {
        currentStatus = status
        guard let status else {
            window?.orderOut(nil)
            return
        }

        let width: CGFloat = status.toolCallCount > 0 ? 46 : 30
        reposition(width: width)

        if window?.contentView == nil || (window?.contentView as? NSHostingView<AgentStatusView>) == nil {
            window?.contentView = NSHostingView(rootView: AgentStatusView(status: status))
        } else {
            (window?.contentView as? NSHostingView<AgentStatusView>)?.rootView = AgentStatusView(status: status)
        }

        window?.orderFrontRegardless()
    }

    /// Sits just to the right of where the collapsed island lands, tracking
    /// the same notch geometry so it stays aligned if the display changes.
    private func reposition(width: CGFloat) {
        guard let panel = window else { return }
        let screenFrame = panel.screen?.frame ?? NSScreen.main?.frame ?? .zero
        let notch = ScreenNotch.size(for: panel.screen)
        let settings = IslandSettings.shared
        let islandHalfWidth = settings.collapsedWindowSize.width / 2

        let gap: CGFloat = 10
        let height: CGFloat = 28
        let origin = NSPoint(
            x: screenFrame.midX + max(islandHalfWidth, notch.width / 2) + gap,
            y: screenFrame.maxY - height - 5
        )
        let frame = NSRect(origin: origin, size: CGSize(width: width, height: height))
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: true)
    }
}
