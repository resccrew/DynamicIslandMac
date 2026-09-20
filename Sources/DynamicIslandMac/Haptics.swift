import AppKit

/// Trackpad feedback. Only Force Touch trackpads actually vibrate; on other
/// input devices these calls are silently ignored, so no capability check is needed.
enum Haptics {
    /// Single crisp tick when the island first notices the pointer. This is the
    /// only feedback the island gives — opening and closing stay silent.
    static func hover() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
