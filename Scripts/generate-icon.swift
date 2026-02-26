import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let bytesPerPixel = 4
let bytesPerRow = size * bytesPerPixel

guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else {
    fputs("Failed to create CGContext.\n", stderr)
    exit(1)
}

let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

ctx.setFillColor(white)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.08))
ctx.setLineWidth(4)
ctx.addPath(CGPath(roundedRect: CGRect(x: 72, y: 72, width: 880, height: 880), cornerWidth: 190, cornerHeight: 190, transform: nil))
ctx.strokePath()

let outer = CGRect(x: 220, y: 210, width: 584, height: 604)
let cornerRadius: CGFloat = 82
let bodyPath = CGMutablePath()
bodyPath.addPath(CGPath(roundedRect: outer, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))

let towerWidth: CGFloat = 92
let towerHeight: CGFloat = 120
let towerGap: CGFloat = 44
let topY = outer.maxY - 26
let leftX = outer.minX + 72
for i in 0..<4 {
    let x = leftX + CGFloat(i) * (towerWidth + towerGap)
    bodyPath.addRoundedRect(in: CGRect(x: x, y: topY, width: towerWidth, height: towerHeight), cornerWidth: 24, cornerHeight: 24)
}

ctx.addPath(bodyPath)
ctx.setFillColor(black)
ctx.fillPath()

// Negative-space doorway for stronger icon legibility at small sizes.
ctx.setBlendMode(.clear)
ctx.fill(CGRect(x: 474, y: 210, width: 76, height: 174))

// Minimal bridge-arch cut to tie back to Drawbridge visual language.
let arch = CGMutablePath()
arch.move(to: CGPoint(x: 340, y: 338))
arch.addQuadCurve(to: CGPoint(x: 684, y: 338), control: CGPoint(x: 512, y: 460))
arch.addLine(to: CGPoint(x: 684, y: 292))
arch.addQuadCurve(to: CGPoint(x: 340, y: 292), control: CGPoint(x: 512, y: 404))
arch.closeSubpath()
ctx.addPath(arch)
ctx.fillPath()

ctx.setBlendMode(.normal)

guard let image = ctx.makeImage() else {
    fputs("Failed to create CGImage.\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: "Assets/AppIcon.iconset/icon_1024x1024.png")
guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fputs("Failed to create image destination.\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
if !CGImageDestinationFinalize(destination) {
    fputs("Failed to write PNG file.\n", stderr)
    exit(1)
}

print("Wrote \(outputURL.path)")
