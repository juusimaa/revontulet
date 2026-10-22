import AuroraCore
import SwiftUI

/// A night sky with stars and an aurora glow whose strength follows the chance level.
/// The sky stays dark in both appearances, like Weather's backgrounds; light mode is a touch bluer.
struct SkyBackground: View {
    var level: ChanceLevel?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(colors: skyColors, startPoint: .top, endPoint: .bottom)
            Stars()
                .opacity(colorScheme == .dark ? 0.9 : 0.6)
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
                Aurora(intensity: intensity, magenta: level == .high,
                       phase: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate)
            }
            .animation(.smooth(duration: 1.2), value: level)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

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

/// Aurora curtains: vertical rays hanging from slowly drifting wavy arcs, brightest at the lower
/// edge and fading upwards, like the real thing.
private struct Aurora: View {
    var intensity: Double
    var magenta: Bool
    var phase: Double

    private struct Curtain {
        var baseline: Double      // lower edge, as a fraction of the height
        var height: Double        // ray length, as a fraction of the height
        var amplitude: Double
        var wavelength: Double
        var speed: Double
        var tilt: Double
        var color: Color
    }

    private static let curtains = [
        Curtain(baseline: 0.36, height: 0.22, amplitude: 0.035, wavelength: 1.4, speed: 0.07, tilt: -0.10,
                color: Color(red: 0.24, green: 0.96, blue: 0.62)),
        Curtain(baseline: 0.27, height: 0.16, amplitude: 0.025, wavelength: 0.9, speed: -0.05, tilt: -0.06,
                color: Color(red: 0.16, green: 0.84, blue: 0.76)),
    ]
    private static let violet = Color(red: 0.75, green: 0.40, blue: 0.95)

    var body: some View {
        Canvas { context, size in
            let w = Double(size.width), h = Double(size.height)
            for (index, curtain) in Self.curtains.enumerated() {
                var x = -20.0
                while x < w + 20 {
                    let u = x / w
                    let offset = Double(index)
                    let angle: Double = u * 2 * Double.pi / curtain.wavelength + phase * curtain.speed + offset * 1.7
                    let wave = sin(angle)
                    let bottom = h * (curtain.baseline + curtain.tilt * u + curtain.amplitude * wave)
                    // Rays vary in length and brightness along the arc.
                    let rayAngle: Double = u * 37 + phase * 0.3 + offset * 4
                    let ray = 0.6 + 0.4 * sin(rayAngle)
                    let top = bottom - h * curtain.height * ray
                    let topColor = magenta && index == 0 ? Self.violet.opacity(0.5) : curtain.color.opacity(0)
                    let gradient = Gradient(stops: [
                        .init(color: topColor, location: 0),
                        .init(color: curtain.color.opacity(0.55 * ray), location: 0.75),
                        .init(color: curtain.color.opacity(0.9 * ray), location: 0.93),
                        .init(color: curtain.color.opacity(0), location: 1),
                    ])
                    context.fill(
                        Path(CGRect(x: x, y: top, width: 5, height: bottom - top + 8)),
                        with: .linearGradient(gradient, startPoint: CGPoint(x: x, y: top),
                                              endPoint: CGPoint(x: x, y: bottom + 8)))
                    x += 4
                }
            }
        }
        .blur(radius: 10)
        .blendMode(.screen)
        .opacity(intensity)
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
