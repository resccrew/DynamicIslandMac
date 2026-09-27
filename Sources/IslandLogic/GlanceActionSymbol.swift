import Foundation

/// The icon a glance's round action button wears; its label becomes the
/// tooltip and accessibility label.
public enum GlanceActionSymbol {
    public static func name(for label: String) -> String {
        switch label {
        case "Подключиться": return "video.fill"
        case "Выполнено": return "checkmark"
        case "Открыть Часы": return "clock"
        default: return "arrow.up.right"
        }
    }
}
