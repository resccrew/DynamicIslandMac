import CoreGraphics

/// Which display the island lives on when more than one is connected.
public enum IslandDisplayPolicy: String, CaseIterable, Sendable {
    /// The display with the menu bar — where the user is looking.
    case primary
    /// The notched built-in panel when present, otherwise the primary display.
    case builtIn

    /// Decodes a stored value; the legacy "automatic" and anything unknown
    /// mean `.primary`.
    public init(stored raw: String?) {
        self = raw.flatMap(Self.init(rawValue:)) ?? .primary
    }
}

/// A display reduced to the numbers the island needs. Built from `NSScreen`
/// by the app; plain values here so the logic is testable without AppKit.
public struct DisplayInfo: Equatable, Sendable {
    public var frame: CGRect
    public var visibleFrame: CGRect
    /// `safeAreaInsets.top` — non-zero only on displays with a camera notch.
    public var safeAreaTop: CGFloat
    /// Widths of the menu bar areas left and right of the notch, if any.
    public var auxiliaryLeftWidth: CGFloat?
    public var auxiliaryRightWidth: CGFloat?
    public var isBuiltIn: Bool
    /// The display that owns the menu bar (`NSScreen.screens.first`).
    public var isPrimary: Bool

    public init(
        frame: CGRect,
        visibleFrame: CGRect,
        safeAreaTop: CGFloat = 0,
        auxiliaryLeftWidth: CGFloat? = nil,
        auxiliaryRightWidth: CGFloat? = nil,
        isBuiltIn: Bool = false,
        isPrimary: Bool = false
    ) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryLeftWidth = auxiliaryLeftWidth
        self.auxiliaryRightWidth = auxiliaryRightWidth
        self.isBuiltIn = isBuiltIn
        self.isPrimary = isPrimary
    }

    public var hasNotch: Bool {
        safeAreaTop > 0 && auxiliaryLeftWidth != nil && auxiliaryRightWidth != nil
    }
}

public enum DisplayGeometry {
    /// Width of the virtual notch drawn on displays without a real one.
    public static let virtualNotchWidth: CGFloat = 190
    /// Never let the virtual notch take more than this share of the width.
    static let maxVirtualNotchWidthFraction: CGFloat = 0.5

    /// The hardware notch where there is one; otherwise a virtual notch exactly
    /// as tall as that display's menu bar, so the idle island reads as part of
    /// the bar instead of a pill hanging below it.
    public static func notchSize(for display: DisplayInfo, statusBarThickness: CGFloat) -> CGSize {
        if display.hasNotch, let left = display.auxiliaryLeftWidth, let right = display.auxiliaryRightWidth {
            return CGSize(width: display.frame.width - left - right, height: display.safeAreaTop)
        }
        return CGSize(
            width: min(virtualNotchWidth, display.frame.width * maxVirtualNotchWidthFraction),
            height: menuBarHeight(for: display, statusBarThickness: statusBarThickness)
        )
    }

    /// Gap between the top of the display and its visible area. Zero when the
    /// menu bar is auto-hidden, in which case the system thickness is used.
    public static func menuBarHeight(for display: DisplayInfo, statusBarThickness: CGFloat) -> CGFloat {
        let gap = display.frame.maxY - display.visibleFrame.maxY
        return gap > 0 ? gap : statusBarThickness
    }

    /// On a display without a hardware notch the collapsed and peek island
    /// must not hang below the menu bar, so its height is capped at the
    /// (virtual) notch height. Width is untouched. On a notched display the
    /// taller-than-notch look is intended and the size passes through.
    public static func collapsedIslandSize(_ requested: CGSize, notch: CGSize, hasNotch: Bool) -> CGSize {
        guard !hasNotch else { return requested }
        return CGSize(width: requested.width, height: min(requested.height, notch.height))
    }

    /// Scale for the collapsed row's content (artwork, equalizer, text,
    /// paddings) so content designed `contentHeight` tall fits a row of
    /// `rowHeight` with `inset` above and below. Never enlarges.
    public static func collapsedContentScale(rowHeight: CGFloat, contentHeight: CGFloat, inset: CGFloat = 2) -> CGFloat {
        guard contentHeight > 0 else { return 1 }
        return min(1, max(0, rowHeight - inset * 2) / contentHeight)
    }

    /// Index of the display to host the island, or nil when there are none.
    /// Falls back to the first display if none claims to be primary, which
    /// matches `NSScreen.screens.first` owning the menu bar.
    public static func preferredDisplay(among displays: [DisplayInfo], policy: IslandDisplayPolicy) -> Int? {
        guard !displays.isEmpty else { return nil }
        let primary = displays.firstIndex(where: \.isPrimary) ?? 0
        switch policy {
        case .primary:
            return primary
        case .builtIn:
            return displays.firstIndex(where: \.isBuiltIn) ?? primary
        }
    }

    /// Bottom-left origin (AppKit coordinates) that pins a container of `size`
    /// to the top-centre of the display.
    public static func panelOrigin(containerSize size: CGSize, on display: DisplayInfo) -> CGPoint {
        CGPoint(x: display.frame.midX - size.width / 2, y: display.frame.maxY - size.height)
    }
}
