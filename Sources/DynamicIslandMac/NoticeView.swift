import SwiftUI

/// The island's hardware announcement, staged the way Dynamic Island does it:
/// the device arrives first with a springy overshoot, the name follows a beat
/// later, and the battery ring winds up last. Everything appearing at once is
/// what made the earlier version feel cheap.
struct NoticeView: View {
    let notice: DeviceNotice
    let accent: Color

    @State private var deviceIn = false
    @State private var textIn = false
    @State private var ringIn = false

    var body: some View {
        HStack(spacing: 10) {
            device
                .font(.system(size: 22, weight: .medium))
                .frame(width: 30, height: 30)
                .scaleEffect(deviceIn ? 1 : 0.35)
                .opacity(deviceIn ? 1 : 0)

            VStack(alignment: .leading, spacing: 1) {
                Text(notice.title)
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

            Spacer(minLength: 6)

            if let level = notice.level {
                batteryRing(level)
                    .opacity(ringIn ? 1 : 0)
                    .scaleEffect(ringIn ? 1 : 0.7)
            }
        }
        .padding(.horizontal, 14)
        .onAppear(perform: stageIn)
    }

    private var subtitle: String? {
        switch notice.kind {
        case .audioConnected: return "Подключены"
        case .powerConnected, .powerDisconnected: return nil
        }
    }

    /// Apple's own AirPods glyphs, via SF Symbols — official, documented, and
    /// rendered in the system's own two-tone style rather than a flat outline.
    private var device: some View {
        Image(systemName: notice.symbol)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white)
    }

    /// Each element gets its own delay so the eye follows one thing at a time.
    private func stageIn() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.58)) {
            deviceIn = true
        }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.8).delay(0.09)) {
            textIn = true
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.65).delay(0.17)) {
            ringIn = true
        }
    }

    private func batteryRing(_ level: Double) -> some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 2.5)

            Circle()
                .trim(from: 0, to: ringIn ? level : 0)
                .stroke(ringColor(level), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.7).delay(0.2), value: ringIn)

            Text("\(Int(level * 100))")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .frame(width: 23, height: 23)
    }

    /// Green like the system's own battery ring, not the track's album-art
    /// tint — a device's charge has nothing to do with what happens to be
    /// playing, and using the accent colour here read as arbitrary.
    private func ringColor(_ level: Double) -> Color {
        level < 0.2 ? .red : .green
    }
}
