import SwiftUI

/// A brief, self-dismissing peek — currently used for the calendar's
/// "next event" check. Staged the way Dynamic Island announces things: the
/// icon arrives first with a springy overshoot, the text follows a beat later.
struct GlanceView: View {
    let title: String
    let subtitle: String?
    var symbol = "calendar"
    let accent: Color

    @State private var iconIn = false
    @State private var textIn = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 26, height: 26)
                .scaleEffect(iconIn ? 1 : 0.35)
                .opacity(iconIn ? 1 : 0)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .opacity(textIn ? 1 : 0)
            .offset(x: textIn ? 0 : -10)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .onAppear(perform: stageIn)
    }

    private func stageIn() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.58)) {
            iconIn = true
        }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.8).delay(0.09)) {
            textIn = true
        }
    }
}
