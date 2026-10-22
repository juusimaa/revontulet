// Renders the app icon: an aurora curtain above a black spruce horizon.
// Development tool only. Usage: swift tools/render-app-icon.swift
// Writes the default, dark and tinted 1024×1024 PNGs into the AppIcon asset.
import AppKit
import CoreImage

let S: CGFloat = 1024
let out = "Revontulet/Resources/Assets.xcassets/AppIcon.appiconset"
let cs = CGColorSpace(name: CGColorSpace.displayP3)!
let ci = CIContext(options: [.workingColorSpace: cs])

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}

func canvas(_ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx)
    return ctx.makeImage()!
}

func blurred(_ image: CGImage, _ radius: Double) -> CGImage {
    let input = CIImage(cgImage: image).clampedToExtent()
    let blurredImage = input.applyingGaussianBlur(sigma: radius).cropped(to: CGRect(x: 0, y: 0, width: S, height: S))
    return ci.createCGImage(blurredImage, from: CGRect(x: 0, y: 0, width: S, height: S), format: .RGBA8, colorSpace: cs)!
}

func linear(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint, locations: [CGFloat]? = nil) {
    let g = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locations)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func sky(_ ctx: CGContext) {
    // y is up in CoreGraphics: top of icon is y = S.
    linear(ctx, [rgb(0.02, 0.04, 0.10), rgb(0.03, 0.09, 0.16), rgb(0.04, 0.14, 0.18)],
           from: CGPoint(x: 0, y: S), to: CGPoint(x: 0, y: 0))
}

func stars(_ ctx: CGContext, count: Int, seed: UInt64, maxY: CGFloat = 1, minY: CGFloat = 0.35) {
    var s = seed
    func rnd() -> CGFloat { s = s &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((s >> 33) % 10000) / 10000 }
    for _ in 0..<count {
        let x = rnd() * S, y = (minY + rnd() * (maxY - minY)) * S, r = 1.5 + rnd() * 3.5
        ctx.setFillColor(rgb(1, 1, 1, 0.35 + rnd() * 0.5))
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }
}

/// Vertical rays along a curve: each ray fades from bright at its foot to transparent at the top.
func curtain(_ ctx: CGContext, curve: (CGFloat) -> CGFloat, height: (CGFloat) -> CGFloat,
             foot: CGColor, top: CGColor, from x0: CGFloat, to x1: CGFloat, step: CGFloat, width: CGFloat) {
    var x = x0
    while x <= x1 {
        let y = curve(x), h = height(x)
        ctx.saveGState()
        ctx.clip(to: CGRect(x: x - width / 2, y: y, width: width, height: h))
        linear(ctx, [foot, top, rgb(0, 0, 0, 0)], from: CGPoint(x: x, y: y), to: CGPoint(x: x, y: y + h),
               locations: [0, 0.35, 1])
        ctx.restoreGState()
        x += step
    }
}

func compose(_ layers: [(CGImage, CGBlendMode)]) -> CGImage {
    canvas { ctx in
        for (image, mode) in layers {
            ctx.setBlendMode(mode)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: S, height: S))
        }
    }
}


func spruces(_ ctx: CGContext, seed: UInt64, ground: CGFloat, minH: CGFloat, varH: CGFloat, color: CGColor) {
    var s = seed
    func rnd() -> CGFloat { s = s &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((s >> 33) % 10000) / 10000 }
    ctx.setFillColor(color)
    ctx.fill(CGRect(x: 0, y: 0, width: S, height: ground + 4))
    var x: CGFloat = -30
    while x < S + 30 {
        let h = minH + rnd() * varH, w = h * (0.22 + rnd() * 0.06)
        let tiers = 9
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0..<tiers {
            // From the bottom up: each tier's branch tip sticks out, then the outline steps back in.
            let t = CGFloat(i) / CGFloat(tiers)
            let y = ground + h * 0.06 + (h * 0.94) * t
            let half = w / 2 * (1 - t) * (0.85 + rnd() * 0.3)
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
        x += w * (0.45 + rnd() * 0.5)
    }
}

func auroraIcon() -> CGImage {
    let base = canvas { sky($0); stars($0, count: 44, seed: 11, minY: 0.2) }
    // The curtain's lower edge sweeps up from the left treeline towards the upper right.
    let edge: (CGFloat) -> CGFloat = { x in
        let t = x / S
        return 250 + 420 * t + 60 * sin(t * .pi * 2.2)
    }
    let rays = canvas { ctx in
        var x: CGFloat = -40
        var seed: UInt64 = 21
        while x <= S + 40 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let r = CGFloat((seed >> 33) % 10000) / 10000
            let t = x / S
            // Rays of uneven brightness, brighter in slow waves along the curtain, like real folds.
            let bright = min(1, 0.45 + 0.4 * r + 0.25 * sin(t * 13))
            let foot = rgb(0.24 * (1 - t) + 0.30 * t, 0.96 * (1 - t) + 0.85 * t, 0.62 * (1 - t) + 0.82 * t, bright)
            let crest = rgb(0.16 + 0.5 * t, 0.70, 0.78 + 0.1 * t, 0.45 * bright)
            curtain(ctx, curve: edge, height: { _ in 260 + 140 * r + 50 * sin(t * 9) },
                    foot: foot, top: crest, from: x, to: x, step: 1, width: 4 + 6 * r)
            x += 4 + 4 * r
        }
    }
    // Light from the curtain's lower edge spills a little way down, so the sky below stays sky.
    let spill = canvas { ctx in
        var x: CGFloat = -40
        while x <= S + 40 {
            let y = edge(x)
            ctx.saveGState()
            ctx.clip(to: CGRect(x: x - 3, y: y - 120, width: 6, height: 120))
            linear(ctx, [rgb(0.24, 0.96, 0.70, 0.35), rgb(0.16, 0.80, 0.78, 0)],
                   from: CGPoint(x: x, y: y), to: CGPoint(x: x, y: y - 120))
            ctx.restoreGState()
            x += 5
        }
    }
    let violet = canvas { ctx in
        curtain(ctx, curve: { edge($0) + 230 }, height: { _ in 200 },
                foot: rgb(0.70, 0.40, 0.95, 0.35), top: rgb(0.85, 0.30, 0.75, 0), from: 380, to: S + 40, step: 6, width: 7)
    }
    let trees = canvas { ctx in
        spruces(ctx, seed: 5, ground: 70, minH: 120, varH: 110, color: rgb(0.03, 0.06, 0.09))
        spruces(ctx, seed: 3, ground: 0, minH: 150, varH: 170, color: rgb(0.005, 0.012, 0.025))
    }
    return compose([(base, .normal), (blurred(violet, 30), .screen), (blurred(spill, 18), .screen), (blurred(rays, 22), .screen),
                    (blurred(rays, 3), .screen), (blurred(rays, 3), .screen), (trees, .normal)])
}

/// Writes an opaque PNG; App Store icons must not have an alpha channel.
func save(_ image: CGImage, _ name: String) {
    let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}

/// Grayscale for the tinted home screen; the system colours it, so light areas carry the shape.
func tinted(_ image: CGImage) -> CGImage {
    let mono = CIImage(cgImage: image).applyingFilter("CIColorControls", parameters: [
        kCIInputSaturationKey: 0, kCIInputContrastKey: 1.35, kCIInputBrightnessKey: -0.02,
    ])
    return ci.createCGImage(mono, from: CGRect(x: 0, y: 0, width: S, height: S), format: .RGBA8, colorSpace: cs)!
}

let icon = auroraIcon()
save(icon, "AppIcon")
// The artwork is already a night sky, so dark mode uses it as is.
save(icon, "AppIcon-Dark")
save(tinted(icon), "AppIcon-Tinted")
