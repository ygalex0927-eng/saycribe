// Vector icon concepts for Saycribe, drawn with CoreGraphics.
// Usage: swiftc -O design/icons.swift -o build/icons && build/icons design/concepts
// Writes full-bleed 1024×1024 PNGs (the squircle mask is applied later by make_icns.py).
import AppKit
import CoreGraphics

let S: CGFloat = 1024

// Palette: warm paper, terracotta, ink.
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let paper = rgb(0xF0EEE6), paperDeep = rgb(0xE6E1D3)
let terra = rgb(0xD97757), terraLight = rgb(0xE9A587), terraDeep = rgb(0xBD5B38)
let ink = rgb(0x141413), inkSoft = rgb(0x2A2826)

func canvas(_ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Top-left origin, y down — easier to reason about.
    ctx.translateBy(x: 0, y: S)
    ctx.scaleBy(x: 1, y: -1)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    draw(ctx)
    return ctx.makeImage()!
}

func save(_ img: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func linear(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radial(_ ctx: CGContext, _ colors: [CGColor], center: CGPoint, radius: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: .drawsAfterEndLocation)
}

/// Warm paper with a soft light falling from the top-left.
func paperBackground(_ ctx: CGContext) {
    linear(ctx, [rgb(0xF5F2EA), paperDeep], from: CGPoint(x: 200, y: 0), to: CGPoint(x: 820, y: S))
    radial(ctx, [rgb(0xFFFFFF, 0.35), rgb(0xFFFFFF, 0)], center: CGPoint(x: 300, y: 220), radius: 620)
}

func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
func mix(_ a: CGColor, _ b: CGColor, _ t: CGFloat) -> CGColor {
    let x = a.components!, y = b.components!
    return CGColor(red: x[0] + (y[0] - x[0]) * t, green: x[1] + (y[1] - x[1]) * t, blue: x[2] + (y[2] - x[2]) * t, alpha: 1)
}

// MARK: A — Quill Wave
// A feather whose barbs are waveform bars: the scribe's quill and the voice in one mark.
// The quill has just written the line trailing behind its nib.
func quillWave(dark: Bool) -> CGImage {
    canvas { ctx in
        if dark {
            linear(ctx, [rgb(0x26231F), ink], from: CGPoint(x: 200, y: 0), to: CGPoint(x: 700, y: S))
            radial(ctx, [rgb(0xD97757, 0.12), rgb(0xD97757, 0)], center: CGPoint(x: 620, y: 470), radius: 520)
        } else {
            paperBackground(ctx)
        }
        let nib = CGPoint(x: 318, y: 742), tip = CGPoint(x: 736, y: 268)
        let len = hypot(tip.x - nib.x, tip.y - nib.y)
        let d = CGPoint(x: (tip.x - nib.x) / len, y: (tip.y - nib.y) / len)
        let n = CGPoint(x: -d.y, y: d.x)

        // Eight barbs: tapered like a feather, uneven like a voice.
        let env: [CGFloat] = [0.40, 0.66, 0.84, 0.96, 1.0, 0.88, 0.66, 0.38]
        let maxHalf: CGFloat = 150, barW: CGFloat = 38, sweep: CGFloat = 40
        ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.setLineWidth(barW)
        for (i, e) in env.enumerated() {
            let t = 0.26 + CGFloat(i) / CGFloat(env.count - 1) * 0.70
            let c = lerp(nib, tip, t)
            let half = maxHalf * e, sw = sweep * e
            let k = CGFloat(i) / CGFloat(env.count - 1)
            ctx.setStrokeColor(mix(terraDeep, terraLight, k * 0.9))
            ctx.move(to: CGPoint(x: c.x + n.x * half + d.x * sw, y: c.y + n.y * half + d.y * sw))
            ctx.addLine(to: c)
            ctx.addLine(to: CGPoint(x: c.x - n.x * half + d.x * sw, y: c.y - n.y * half + d.y * sw))
            ctx.strokePath()
        }
        // Rachis: a hairline in the background colour splits each barb into two vanes.
        ctx.setStrokeColor(dark ? rgb(0x1E1C1A) : rgb(0xF1EEE6))
        ctx.setLineWidth(10)
        ctx.move(to: lerp(nib, tip, 0.22)); ctx.addLine(to: lerp(nib, tip, 1.03)); ctx.strokePath()

        // Calamus down to the nib.
        let strokeInk = dark ? paper : ink
        ctx.setStrokeColor(strokeInk)
        ctx.setLineWidth(15)
        ctx.move(to: nib); ctx.addLine(to: lerp(nib, tip, 0.22)); ctx.strokePath()

    }
}

// MARK: B — Voice Nib
// A fountain-pen nib on ink; its breather hole is a tiny waveform and the slit runs down to the point.
func voiceNib(dark: Bool) -> CGImage {
    canvas { ctx in
        if dark {
            linear(ctx, [rgb(0x26231F), ink], from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: S))
            radial(ctx, [rgb(0xD97757, 0.10), rgb(0xD97757, 0)], center: CGPoint(x: 512, y: 430), radius: 520)
        } else {
            paperBackground(ctx)
        }

        // Classic nib: narrow collar, flared shoulders, straight tines to a sharp point.
        let nibPath = CGMutablePath()
        nibPath.move(to: CGPoint(x: 512, y: 860))
        nibPath.addLine(to: CGPoint(x: 352, y: 520))
        nibPath.addCurve(to: CGPoint(x: 392, y: 330), control1: CGPoint(x: 330, y: 452), control2: CGPoint(x: 336, y: 380))
        nibPath.addLine(to: CGPoint(x: 404, y: 196))
        nibPath.addQuadCurve(to: CGPoint(x: 620, y: 196), control: CGPoint(x: 512, y: 176))
        nibPath.addLine(to: CGPoint(x: 632, y: 330))
        nibPath.addCurve(to: CGPoint(x: 672, y: 520), control1: CGPoint(x: 688, y: 380), control2: CGPoint(x: 694, y: 452))
        nibPath.closeSubpath()
        ctx.saveGState()
        ctx.addPath(nibPath); ctx.clip()
        linear(ctx, [terraLight, terra, terraDeep], from: CGPoint(x: 400, y: 190), to: CGPoint(x: 620, y: 860))
        // Left facet catches the light, like a curved metal nib.
        ctx.setFillColor(rgb(0xFFFFFF, 0.08))
        ctx.fill(CGRect(x: 0, y: 0, width: 512, height: S))
        ctx.restoreGState()

        ctx.setStrokeColor(ink); ctx.setLineCap(.round); ctx.setLineWidth(12)
        ctx.move(to: CGPoint(x: 512, y: 560)); ctx.addLine(to: CGPoint(x: 512, y: 826)); ctx.strokePath()

        let heights: [CGFloat] = [44, 88, 128, 88, 44]
        ctx.setStrokeColor(paper); ctx.setLineWidth(22)
        for (i, h) in heights.enumerated() {
            let x = 512 + CGFloat(i - 2) * 40
            ctx.move(to: CGPoint(x: x, y: 450 - h / 2)); ctx.addLine(to: CGPoint(x: x, y: 450 + h / 2)); ctx.strokePath()
        }
    }
}

// MARK: C — Spoken Line
// A paper speech bubble on terracotta; inside, a hand-drawn line starts as a voice wave and settles into writing.
func spokenLine() -> CGImage {
    canvas { ctx in
        linear(ctx, [terraLight, terra, terraDeep], from: CGPoint(x: 150, y: 80), to: CGPoint(x: 880, y: 960))
        radial(ctx, [rgb(0xFFFFFF, 0.16), rgb(0xFFFFFF, 0)], center: CGPoint(x: 280, y: 200), radius: 600)

        // Bubble with a soft drop shadow.
        let bubble = CGMutablePath()
        bubble.addRoundedRect(in: CGRect(x: 214, y: 254, width: 596, height: 432), cornerWidth: 168, cornerHeight: 168)
        bubble.move(to: CGPoint(x: 330, y: 640))
        bubble.addCurve(to: CGPoint(x: 268, y: 790), control1: CGPoint(x: 330, y: 700), control2: CGPoint(x: 312, y: 760))
        bubble.addCurve(to: CGPoint(x: 470, y: 676), control1: CGPoint(x: 360, y: 770), control2: CGPoint(x: 430, y: 720))
        bubble.closeSubpath()
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: rgb(0x5A2A18, 0.28))
        ctx.addPath(bubble); ctx.setFillColor(paper); ctx.fillPath()
        ctx.restoreGState()

        // The line: decaying sine → flat stroke.
        let line = CGMutablePath()
        let x0: CGFloat = 318, x1: CGFloat = 706, y: CGFloat = 470, waveEnd: CGFloat = 560
        line.move(to: CGPoint(x: x0, y: y))
        var x = x0
        while x <= x1 {
            let k = max(0, 1 - (x - x0) / (waveEnd - x0))
            let amp = 92 * k * k
            let yy = y - amp * sin((x - x0) / 26 * .pi * 0.9)
            line.addLine(to: CGPoint(x: x, y: yy))
            x += 2
        }
        ctx.addPath(line)
        ctx.setStrokeColor(ink); ctx.setLineWidth(20); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.strokePath()
        // Cursor dot where the writing continues.
        ctx.setFillColor(terra)
        ctx.fillEllipse(in: CGRect(x: x1 + 26, y: y - 15, width: 30, height: 30))
    }
}

// MARK: Menu bar template
// Solid nib silhouette with three waveform bars and the slit cut out; macOS tints it for light/dark menu bars.
func menuBarNib() -> CGImage {
    canvas { ctx in
        let nibPath = CGMutablePath()
        nibPath.move(to: CGPoint(x: 512, y: 1000))
        nibPath.addLine(to: CGPoint(x: 250, y: 560))
        nibPath.addCurve(to: CGPoint(x: 330, y: 270), control1: CGPoint(x: 214, y: 460), control2: CGPoint(x: 230, y: 340))
        nibPath.addLine(to: CGPoint(x: 346, y: 40))
        nibPath.addQuadCurve(to: CGPoint(x: 678, y: 40), control: CGPoint(x: 512, y: 14))
        nibPath.addLine(to: CGPoint(x: 694, y: 270))
        nibPath.addCurve(to: CGPoint(x: 774, y: 560), control1: CGPoint(x: 794, y: 340), control2: CGPoint(x: 810, y: 460))
        nibPath.closeSubpath()
        ctx.addPath(nibPath); ctx.setFillColor(rgb(0x000000)); ctx.fillPath()

        ctx.setBlendMode(.clear)
        ctx.setLineCap(.round)
        ctx.setLineWidth(64)
        for (i, h) in [CGFloat(110), 220, 110].enumerated() {
            let x = 512 + CGFloat(i - 1) * 118
            ctx.move(to: CGPoint(x: x, y: 420 - h / 2)); ctx.addLine(to: CGPoint(x: x, y: 420 + h / 2)); ctx.strokePath()
        }
        ctx.setLineWidth(46)
        ctx.move(to: CGPoint(x: 512, y: 610)); ctx.addLine(to: CGPoint(x: 512, y: 930)); ctx.strokePath()
    }
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
save(quillWave(dark: false), "\(out)/A_quill_wave.png")
save(quillWave(dark: true), "\(out)/A2_quill_wave_dark.png")
save(voiceNib(dark: true), "\(out)/B_voice_nib.png")
save(voiceNib(dark: false), "\(out)/B2_voice_nib_paper.png")
save(menuBarNib(), "\(out)/menubar_nib_1024.png")
print("ok")
