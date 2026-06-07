// Draws the Söyle app icon (NVIDIA-green squircle + white microphone) at a given
// pixel size, with CoreGraphics only (no AppKit / WindowServer needed).
// usage: swift make_icon.swift <pixelSize> <outPath.png>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3, let size = Int(args[1]) else {
    FileHandle.standardError.write(Data("usage: make_icon.swift <size> <out.png>\n".utf8)); exit(2)
}
let out = URL(fileURLWithPath: args[2])
let S = CGFloat(size)

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}
let nvidia = color(0x76/255, 0xB9/255, 0x00/255)
let white = color(1, 1, 1)

// Background squircle (small margin, large corner radius — macOS look).
let margin = S * 0.085
let rect = CGRect(x: margin, y: margin, width: S - 2*margin, height: S - 2*margin)
let radius = (S - 2*margin) * 0.235
let bg = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.addPath(bg); ctx.setFillColor(nvidia); ctx.fillPath()

// Microphone, white, centered.
let cx = S * 0.5
let bodyW = S * 0.24
let bodyH = S * 0.40
let bodyTop = S * 0.78      // CG origin is bottom-left; raised so the mic sits centered
let bodyBottom = bodyTop - bodyH
let body = CGRect(x: cx - bodyW/2, y: bodyBottom, width: bodyW, height: bodyH)
let bodyPath = CGPath(roundedRect: body, cornerWidth: bodyW/2, cornerHeight: bodyW/2, transform: nil)
ctx.addPath(bodyPath); ctx.setFillColor(white); ctx.fillPath()

// Cradle: a U-shaped arc (opening upward) hugging the lower half of the body.
let lw = S * 0.05
ctx.setStrokeColor(white); ctx.setLineWidth(lw); ctx.setLineCap(.round)
let cradleR = bodyW * 0.92
let cradleCenterY = bodyBottom + bodyH * 0.34
ctx.addArc(center: CGPoint(x: cx, y: cradleCenterY), radius: cradleR,
           startAngle: .pi, endAngle: 0, clockwise: false)
ctx.strokePath()

// Stem + base.
let stemTop = cradleCenterY - cradleR
let baseY = stemTop - S * 0.085
ctx.move(to: CGPoint(x: cx, y: stemTop)); ctx.addLine(to: CGPoint(x: cx, y: baseY)); ctx.strokePath()
ctx.move(to: CGPoint(x: cx - S*0.11, y: baseY)); ctx.addLine(to: CGPoint(x: cx + S*0.11, y: baseY)); ctx.strokePath()

guard let img = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)
else { exit(1) }
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
