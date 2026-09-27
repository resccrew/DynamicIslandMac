import Foundation

/// Presets only set values that already exist in `IslandSettings`; there is no
/// separate stored "preset" — the picker shows whichever preset the current
/// values match, or «Другой» once the advanced sliders moved them.
private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }

enum IslandSizePreset: CaseIterable, Identifiable {
    case compact
    case standard
    case large

    var id: Self { self }

    var title: String {
        switch self {
        case .compact: return "Компактный"
        case .standard: return "Стандартный"
        case .large: return "Крупный"
        }
    }

    /// Width of the expanded card.
    var expandedWidth: Double {
        switch self {
        case .compact: return 318
        case .standard: return 336
        case .large: return 360
        }
    }

    func apply(to settings: IslandSettings) {
        settings.expandedWidth = expandedWidth
    }

    static func matching(_ settings: IslandSettings) -> IslandSizePreset? {
        allCases.first { close($0.expandedWidth, settings.expandedWidth) }
    }
}

enum HoverPreset: CaseIterable, Identifiable {
    case off
    case light
    case pronounced

    var id: Self { self }

    var title: String {
        switch self {
        case .off: return "Нет"
        case .light: return "Лёгкая"
        case .pronounced: return "Заметная"
        }
    }

    var widthGrowth: Double {
        switch self {
        case .off: return 0
        case .light: return IslandSettings.Defaults.peekWidthGrowth
        case .pronounced: return 32
        }
    }

    var heightGrowth: Double {
        switch self {
        case .off: return 0
        case .light: return IslandSettings.Defaults.peekHeightGrowth
        case .pronounced: return 10
        }
    }

    func apply(to settings: IslandSettings) {
        settings.peekWidthGrowth = widthGrowth
        settings.peekHeightGrowth = heightGrowth
    }

    static func matching(_ settings: IslandSettings) -> HoverPreset? {
        allCases.first {
            close($0.widthGrowth, settings.peekWidthGrowth) && close($0.heightGrowth, settings.peekHeightGrowth)
        }
    }
}

enum AnimationPreset: CaseIterable, Identifiable {
    case fast
    case normal
    case smooth

    var id: Self { self }

    var title: String {
        switch self {
        case .fast: return "Быстрая"
        case .normal: return "Обычная"
        case .smooth: return "Плавная"
        }
    }

    var duration: Double {
        switch self {
        case .fast: return 0.24
        case .normal: return IslandSettings.Defaults.animationDuration
        case .smooth: return 0.45
        }
    }

    func apply(to settings: IslandSettings) {
        settings.animationDuration = duration
    }

    static func matching(_ settings: IslandSettings) -> AnimationPreset? {
        allCases.first { close($0.duration, settings.animationDuration) }
    }
}
