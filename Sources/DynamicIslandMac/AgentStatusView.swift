import SwiftUI

/// A small companion pill next to the island showing whether Claude Code is
/// currently working in a terminal, and how many tools it has called in the
/// turn so far. Purely a glance indicator — no conversation content, just the
/// two numbers `ClaudeAgentMonitor` derives from the transcript's shape.
struct AgentStatusView: View {
    let status: ClaudeAgentMonitor.Status

    @State private var spin = false

    var body: some View {
        ZStack {
            Capsule().fill(Color.black)

            HStack(spacing: 5) {
                spinner
                if status.toolCallCount > 0 {
                    Text("\(status.toolCallCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .transition(.opacity)
                }
            }
        }
        .frame(width: status.toolCallCount > 0 ? 46 : 30, height: 28)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: status.toolCallCount)
        .onAppear { startSpinIfNeeded() }
        .onChange(of: status.isActive) { _ in startSpinIfNeeded() }
    }

    private var spinner: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.22), lineWidth: 2)
                .frame(width: 14, height: 14)

            if status.isActive {
                Circle()
                    .trim(from: 0, to: 0.65)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(spin ? 360 : 0))
            } else {
                Circle()
                    .fill(.white.opacity(0.55))
                    .frame(width: 5, height: 5)
            }
        }
    }

    private func startSpinIfNeeded() {
        guard status.isActive else {
            spin = false
            return
        }
        spin = false
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
            spin = true
        }
    }
}
