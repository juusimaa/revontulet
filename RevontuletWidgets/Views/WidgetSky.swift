import AuroraCore
import SwiftUI

/// The app's night sky as a still frame, for the widget background: stars, the shared aurora curtains
/// at the widget framing, and a dark fade at the bottom that keeps the text readable.
struct WidgetSky: View {
    var level: ChanceLevel?
    /// Old data: the artwork is dimmed to 20% of its level strength (the text stays at full contrast).
    var isStale = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.004, green: 0.03, blue: 0.06), Color(red: 0.03, green: 0.08, blue: 0.12),
                                    Color(red: 0.04, green: 0.11, blue: 0.15)],
                           startPoint: .top, endPoint: .bottom)
            Stars().opacity(0.8)
            AuroraCurtains(intensity: intensity, magenta: level == .high, phase: 0, framing: .widget)
            LinearGradient(stops: [.init(color: .clear, location: 0.3), .init(color: Color(red: 0.004, green: 0.03, blue: 0.06).opacity(0.7), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .accessibilityHidden(true)
    }

    private var intensity: Double {
        let base = switch level {
        case .high: 0.85
        case .moderate: 0.55
        case .low: 0.3
        case ChanceLevel.none?: 0.12
        case nil: 0.12
        }
        return isStale ? base * 0.2 : base
    }
}

extension AuroraEntry {
    /// Old data: the sky is dimmed and the views say so in words.
    var isStale: Bool {
        if case .stale = state { true } else { false }
    }
}

/// The small "Sample" marker the gallery and placeholder entries carry, so they never pass as real data.
struct WidgetSampleBadge: View {
    var body: some View {
        Text("Sample")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.white.opacity(0.22), in: .capsule)
            .lineLimit(1)
            .fixedSize()
    }
}

/// A fixed, deterministic star field, densest at the top.
private struct Stars: View {
    var body: some View {
        Canvas { context, size in
            var state: UInt64 = 0xA0_2026
            func next() -> UInt64 {
                state &+= 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                return z ^ (z >> 31)
            }
            for _ in 0..<45 {
                let x = Double(next() % 10_000) / 10_000 * size.width
                let t = Double(next() % 10_000) / 10_000
                let y = t * t * size.height * 0.7
                let radius = 0.4 + Double(next() % 100) / 100 * 0.7
                let alpha = 0.25 + Double(next() % 100) / 100 * 0.6
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                             with: .color(.white.opacity(alpha * (1 - t * 0.6))))
            }
        }
    }
}
