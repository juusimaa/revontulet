import AuroraCore
import SwiftUI

/// A night sky with stars and an aurora glow whose strength follows the chance level.
/// The sky stays dark in both appearances, like Weather's backgrounds; light mode is a touch bluer.
struct SkyBackground: View {
    var level: ChanceLevel?
    /// false for a still sky, e.g. behind a list where the motion would not be seen.
    var animated = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Time spent paused so far, taken out of the phase so the curtains resume where they stopped.
    @State private var pausedTotal: TimeInterval = 0
    /// When the sky was paused (hidden behind the map page or a sheet); nil while it moves.
    @State private var pausedAt: Date?

    var body: some View {
        ZStack {
            LinearGradient(colors: skyColors, startPoint: .top, endPoint: .bottom)
            Stars()
                .opacity(colorScheme == .dark ? 0.9 : 0.6)
            // The curtains drift slowly, so 15 frames a second looks as smooth as 30 at half the cost.
            TimelineView(.animation(minimumInterval: 1 / 15, paused: isStill)) { context in
                AuroraCurtains(intensity: intensity, magenta: level == .high,
                               phase: reduceMotion ? 0 : (pausedAt ?? context.date).timeIntervalSinceReferenceDate - pausedTotal)
            }
            .animation(.smooth(duration: 1.2), value: level)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onChange(of: animated, initial: true) { _, animated in
            if !animated {
                if pausedAt == nil { pausedAt = .now }
            } else if let pausedAt {
                pausedTotal += Date.now.timeIntervalSince(pausedAt)
                self.pausedAt = nil
            }
        }
    }

    private var isStill: Bool { reduceMotion || !animated }

    private var skyColors: [Color] {
        colorScheme == .dark
            ? [Color(red: 0.01, green: 0.03, blue: 0.08), Color(red: 0.03, green: 0.08, blue: 0.14), Color(red: 0.04, green: 0.11, blue: 0.15)]
            : [Color(red: 0.05, green: 0.11, blue: 0.24), Color(red: 0.09, green: 0.20, blue: 0.33), Color(red: 0.13, green: 0.27, blue: 0.36)]
    }

    private var intensity: Double {
        switch level {
        case .high: 0.85
        case .moderate: 0.55
        case .low: 0.3
        case ChanceLevel.none?: 0.12
        case nil: 0.18
        }
    }
}

/// A fixed, deterministic star field, densest at the top of the sky.
private struct Stars: View {
    var body: some View {
        Canvas { context, size in
            var generator = SplitMix(seed: 0xA0_2026)
            for _ in 0..<110 {
                let x = Double(generator.next() % 10_000) / 10_000 * size.width
                let t = Double(generator.next() % 10_000) / 10_000
                let y = t * t * size.height * 0.75
                let radius = 0.4 + Double(generator.next() % 100) / 100 * 0.9
                let alpha = 0.25 + Double(generator.next() % 100) / 100 * 0.6
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                             with: .color(.white.opacity(alpha * (1 - t * 0.6))))
            }
        }
    }
}

private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

#Preview {
    SkyBackground(level: .high)
}
