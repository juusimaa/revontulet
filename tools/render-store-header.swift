// Renders the App Store creative assets: the app icon's aurora curtain above a spruce horizon with the
// app name in the centre, as the 21:9 product page header and the 3:2 search results image.
// Development tool only. Usage: swift tools/render-store-header.swift [output directory]
// Writes store-header.png (3840 × 1646) and search-result.png (3840 × 2560), each with a text-free
// variant; all opaque PNGs in Display P3. The name is the same in every language, so one image per
// format serves all localizations.
import AppKit
import CoreImage

/// The canvas being drawn. Vertical sizes are designed for the 1646-pixel-high header and scale with
/// `k`, so every format keeps the same proportions.
var W: CGFloat = 3840, H: CGFloat = 1646
var k: CGFloat { H / 1646 }
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "app-store-header"
let cs = CGColorSpace(name: CGColorSpace.displayP3)!
let ci = CIContext(options: [.workingColorSpace: cs])

let title = "Revontulet"

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}

func canvas(_ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx)
    return ctx.makeImage()!
}

func blurred(_ image: CGImage, _ radius: Double) -> CGImage {
    let rect = CGRect(x: 0, y: 0, width: W, height: H)
    let output = CIImage(cgImage: image).clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: rect)
    return ci.createCGImage(output, from: rect, format: .RGBA8, colorSpace: cs)!
}

func linear(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint, locations: [CGFloat]? = nil) {
    let g = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locations)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

struct Random {
    var s: UInt64
    mutating func next() -> CGFloat {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((s >> 33) % 10000) / 10000
    }
}

func sky(_ ctx: CGContext) {
    // y is up in CoreGraphics: the top of the image is y = H.
    linear(ctx, [rgb(0.02, 0.04, 0.10), rgb(0.025, 0.06, 0.12), rgb(0.03, 0.09, 0.14)],
           from: CGPoint(x: 0, y: H), to: CGPoint(x: 0, y: 0))
}

func stars(_ ctx: CGContext, count: Int, seed: UInt64) {
    var r = Random(s: seed)
    for _ in 0..<count {
        let x = r.next() * W, y = (0.25 + r.next() * 0.75) * H, size = 1.5 + r.next() * 4
        ctx.setFillColor(rgb(1, 1, 1, 0.3 + r.next() * 0.55))
        ctx.fillEllipse(in: CGRect(x: x - size, y: y - size, width: 2 * size, height: 2 * size))
    }
}

/// Vertical rays along a curve: each ray fades from bright at its foot to transparent at the top.
func ray(_ ctx: CGContext, x: CGFloat, foot y: CGFloat, height h: CGFloat, width: CGFloat, foot: CGColor, top: CGColor) {
    ctx.saveGState()
    // The foot fades in over a short distance, so the lower edge is soft rather than a drawn line.
    let lead: CGFloat = 70 * k
    ctx.clip(to: CGRect(x: x - width / 2, y: y - lead, width: width, height: h + lead))
    linear(ctx, [rgb(0, 0, 0, 0), foot, top, rgb(0, 0, 0, 0)], from: CGPoint(x: x, y: y - lead),
           to: CGPoint(x: x, y: y + h), locations: [0, lead / (h + lead), 0.4, 1])
    ctx.restoreGState()
}

func compose(_ layers: [(CGImage, CGBlendMode)]) -> CGImage {
    canvas { ctx in
        for (image, mode) in layers {
            ctx.setBlendMode(mode)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: W, height: H))
        }
    }
}

func spruces(_ ctx: CGContext, seed: UInt64, ground: CGFloat, minH: CGFloat, varH: CGFloat, color: CGColor) {
    var r = Random(s: seed)
    ctx.setFillColor(color)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: ground + 4))
    var x: CGFloat = -40
    while x < W + 40 {
        let h = minH + r.next() * varH, w = h * (0.22 + r.next() * 0.06)
        let tiers = 9
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0..<tiers {
            let t = CGFloat(i) / CGFloat(tiers)
            let y = ground + h * 0.06 + (h * 0.94) * t
            let half = w / 2 * (1 - t) * (0.85 + r.next() * 0.3)
            left += [CGPoint(x: x - half, y: y), CGPoint(x: x - half * 0.35, y: y + h * 0.05)]
            right += [CGPoint(x: x + half, y: y), CGPoint(x: x + half * 0.35, y: y + h * 0.05)]
        }
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x - 3, y: ground))
        left.forEach { p.addLine(to: $0) }
        p.addLine(to: CGPoint(x: x, y: ground + h))
        right.reversed().forEach { p.addLine(to: $0) }
        p.addLine(to: CGPoint(x: x + 3, y: ground))
        p.closeSubpath()
        ctx.addPath(p)
        ctx.fillPath()
        x += w * (0.45 + r.next() * 0.5)
    }
}

/// As in the icon, the curtain's lower edge sweeps up from left to right with one fold, and stays
/// above the phrase.
func edge(_ x: CGFloat) -> CGFloat {
    let t = x / W
    return H * (0.56 + 0.16 * t + 0.06 * sin(t * .pi * 2.4 + 0.3))
}

/// How lit the curtain is along its length: bright folds with darker gaps, so it reads as a ribbon
/// of light rather than a wall.
func patch(_ t: CGFloat) -> CGFloat {
    let a = 0.5 + 0.5 * sin(t * .pi * 2.6 + 3.77), b = 0.5 + 0.5 * sin(t * .pi * 7.3 + 1.9)
    return max(0, min(1, 0.15 + 0.75 * a * a + 0.35 * b - 0.15))
}

func artwork() -> CGImage {
    let base = canvas { sky($0); stars($0, count: Int(160 * k), seed: 11) }
    let rays = canvas { ctx in
        var r = Random(s: 21)
        var x: CGFloat = -60
        while x <= W + 60 {
            let n = r.next(), t = x / W
            let bright = patch(t) * (0.55 + 0.45 * n)
            let foot = rgb(0.24 * (1 - t) + 0.30 * t, 0.96 * (1 - t) + 0.85 * t, 0.62 * (1 - t) + 0.82 * t, bright)
            let crest = rgb(0.16 + 0.5 * t, 0.70, 0.78 + 0.1 * t, 0.45 * bright)
            ray(ctx, x: x, foot: edge(x), height: (300 + 160 * n) * k * (0.6 + 0.6 * patch(t)), width: 8 + 12 * n,
                foot: foot, top: crest)
            x += 8 + 8 * n
        }
    }
    // Light from the lower edge spills a little way down, so the sky below stays sky.
    let spill = canvas { ctx in
        var x: CGFloat = -60
        while x <= W + 60 {
            let y = edge(x)
            ctx.saveGState()
            ctx.clip(to: CGRect(x: x - 5, y: y - 70 * k, width: 10, height: 70 * k))
            linear(ctx, [rgb(0.24, 0.96, 0.70, 0.22 * patch(x / W)), rgb(0.16, 0.80, 0.78, 0)],
                   from: CGPoint(x: x, y: y), to: CGPoint(x: x, y: y - 70 * k))
            ctx.restoreGState()
            x += 9
        }
    }
    let violet = canvas { ctx in
        var x: CGFloat = W * 0.35
        while x <= W + 60 {
            ray(ctx, x: x, foot: edge(x) + 380 * k, height: 300 * k, width: 12,
                foot: rgb(0.70, 0.40, 0.95, 0.30), top: rgb(0.85, 0.30, 0.75, 0))
            x += 11
        }
    }
    let trees = canvas { ctx in
        spruces(ctx, seed: 5, ground: 120 * k, minH: 170 * k, varH: 150 * k, color: rgb(0.03, 0.06, 0.09))
        spruces(ctx, seed: 3, ground: 0, minH: 210 * k, varH: 230 * k, color: rgb(0.005, 0.012, 0.025))
    }
    return compose([(base, .normal), (blurred(violet, 55), .screen), (blurred(spill, 14), .screen),
                    (blurred(rays, 40), .screen), (blurred(rays, 5), .screen), (blurred(rays, 5), .screen),
                    (trees, .normal)])
}

/// The name, centred under the brightest fold, with a soft shadow so it reads over the sky on any device.
func withTitle(_ art: CGImage, _ text: String) -> CGImage {
    canvas { ctx in
        ctx.draw(art, in: CGRect(x: 0, y: 0, width: W, height: H))
        let font = NSFont.systemFont(ofSize: 230 * k, weight: .bold)
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor(cgColor: rgb(0.96, 0.98, 1))!, .kern: -3 * k,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let x = (W - bounds.width) / 2 - bounds.minX
        let y = H * 0.42 - bounds.height / 2 - bounds.minY
        ctx.setShadow(offset: .zero, blur: 60, color: rgb(0.01, 0.03, 0.07, 0.9))
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
    }
}

/// Writes an opaque PNG; the App Store rejects artwork with an alpha channel.
func save(_ image: CGImage, _ name: String) {
    let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}

for (name, width, height) in [("store-header", 3840, 1646), ("search-result", 3840, 2560)] as [(String, CGFloat, CGFloat)] {
    W = width
    H = height
    let art = artwork()
    save(art, "\(name)-textless")
    save(withTitle(art, title), name)
}
