import SwiftUI
import AuroraCore

/// Vector aurora glyph (curtain with rays), translated from the `#aurora`
/// symbol in the widget UI draft (16x16 viewBox, 1.5 stroke, round caps).
/// Template style: draws with the current foreground style, so callers tint it.
struct AuroraGlyph: View {
    /// Kept for callers; the draft glyph does not vary with the level.
    var level: ChanceLevel? = nil

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            AuroraGlyphShape()
                .stroke(style: StrokeStyle(lineWidth: side * 1.5 / 16, lineCap: .round, lineJoin: .round))
                .frame(width: side, height: side)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct AuroraGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16
        let ox = rect.midX - 8 * s
        let oy = rect.midY - 8 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }

        var path = Path()
        // Curtain: M1.5 5.5 c2-2.2 4-2.2 6.5 0 s4.5 2.2 6.5 0
        path.move(to: p(1.5, 5.5))
        path.addCurve(to: p(8, 5.5), control1: p(3.5, 3.3), control2: p(5.5, 3.3))
        path.addCurve(to: p(14.5, 5.5), control1: p(10.5, 7.7), control2: p(12.5, 7.7))
        // Rays
        let rays: [(CGFloat, CGFloat, CGFloat)] = [
            (3, 6.6, 12.6), (6, 7.4, 11.6), (8.8, 7.8, 13.8), (11.6, 7.3, 11.3), (14, 6.2, 9.2),
        ]
        for (x, y0, y1) in rays {
            path.move(to: p(x, y0))
            path.addLine(to: p(x, y1))
        }
        return path
    }
}

#Preview {
    VStack(spacing: 16) {
        ForEach([Color.green, .yellow, .pink, .white], id: \.self) { color in
            HStack(spacing: 24) {
                AuroraGlyph().frame(width: 16, height: 16)
                AuroraGlyph().frame(width: 28, height: 28)
                AuroraGlyph().frame(width: 60, height: 60)
            }
            .foregroundStyle(color)
        }
    }
    .padding(24)
    .background(Color(red: 0.03, green: 0.05, blue: 0.12))
}
