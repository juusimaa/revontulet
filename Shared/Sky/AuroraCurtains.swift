import SwiftUI

/// Aurora curtains: vertical rays hanging from slowly drifting wavy arcs, brightest at the lower
/// edge and fading upwards, like the real thing. Shared by the app's sky and the widgets.
struct AuroraCurtains: View {
    var intensity: Double
    var magenta: Bool
    var phase: Double
    var framing: Framing = .screen

    /// Where the curtains hang and how tall their rays are, so one drawing fits both a full screen and a widget.
    struct Framing: Sendable {
        /// Lower edge of each curtain as a fraction of the height.
        var baselines: [Double]
        /// Multiplier for the ray lengths.
        var heightScale: Double
        /// Blur radius in points: the full screen is soft, a small widget needs the text to stay clear.
        var blur: Double

        /// The full-screen sky: curtains in the upper half.
        static let screen = Framing(baselines: [0.36, 0.27], heightScale: 1, blur: 10)
        /// Widgets are short, so the curtains hang lower with longer rays (from the widget draft).
        static let widget = Framing(baselines: [0.62, 0.52], heightScale: 1.3, blur: 5)
    }

    private struct Curtain {
        var height: Double        // ray length, as a fraction of the height
        var amplitude: Double
        var wavelength: Double
        var speed: Double
        var tilt: Double
        var color: Color
    }

    private static let curtains = [
        Curtain(height: 0.22, amplitude: 0.035, wavelength: 1.4, speed: 0.07, tilt: -0.10,
                color: Color(red: 0.24, green: 0.96, blue: 0.62)),
        Curtain(height: 0.16, amplitude: 0.025, wavelength: 0.9, speed: -0.05, tilt: -0.06,
                color: Color(red: 0.16, green: 0.84, blue: 0.76)),
    ]
    private static let violet = Color(red: 0.75, green: 0.40, blue: 0.95)

    var body: some View {
        Canvas { context, size in
            let w = Double(size.width), h = Double(size.height)
            for (index, curtain) in Self.curtains.enumerated() {
                let baseline = framing.baselines[index]
                var x = -20.0
                while x < w + 20 {
                    let u = x / w
                    let offset = Double(index)
                    let angle: Double = u * 2 * Double.pi / curtain.wavelength + phase * curtain.speed + offset * 1.7
                    let wave = sin(angle)
                    let bottom = h * (baseline + curtain.tilt * u + curtain.amplitude * wave)
                    // Rays vary in length and brightness along the arc.
                    let rayAngle: Double = u * 37 + phase * 0.3 + offset * 4
                    let ray = 0.6 + 0.4 * sin(rayAngle)
                    let top = bottom - h * curtain.height * framing.heightScale * ray
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
        .blur(radius: framing.blur)
        .blendMode(.screen)
        .opacity(intensity)
    }
}
