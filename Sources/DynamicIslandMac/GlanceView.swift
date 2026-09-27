import SwiftUI
import IslandLogic

/// A brief, self-dismissing peek — the calendar's "next event", a finished
/// timer. Same card frame and header as the expanded cards. Staged the way
/// Dynamic Island announces things: the icon springs in, the row fades in a
/// beat behind it (fade only under Reduce Motion).
struct GlanceView: View {
    let title: String
    let subtitle: String?
    var symbol = "calendar"
    let accent: Color
    /// «Подключиться» for a call link, «Выполнено» for a reminder.
    var actionLabel: String? = nil
    var onAction: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var iconIn = false
    @State private var textIn = false

    private enum Stage {
        static let iconScale: CGFloat = 0.35
        static let textDelay = 0.09
    }

    var body: some View {
        // A missing subtitle still holds its line, so the title keeps one baseline.
        CardHeader(title: title, subtitle: subtitle ?? " ") {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: DS.Card.headerIcon, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: DS.Card.headerIconColumn.pt)
                .scaleEffect(iconIn || reduceMotion ? 1 : Stage.iconScale)
        } trailing: {
            if let actionLabel {
                CardPrimaryButton(
                    symbol: GlanceActionSymbol.name(for: actionLabel),
                    fill: accent,
                    help: actionLabel,
                    action: onAction
                )
                .layoutPriority(1)
            }
        }
        .opacity(textIn ? 1 : 0)
        .offset(x: textIn || reduceMotion ? 0 : -DS.Space.m.pt)
        .padding(.horizontal, DS.Space.cardSide.pt)
        .frame(maxHeight: .infinity)
        .onAppear(perform: stageIn)
    }

    private func stageIn() {
        withAnimation(.dsState(reduceMotion: reduceMotion)) {
            iconIn = true
        }
        withAnimation(.dsFade(reduceMotion: reduceMotion).delay(reduceMotion ? 0 : Stage.textDelay)) {
            textIn = true
        }
    }
}
