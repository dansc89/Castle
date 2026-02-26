import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift Scripts/prepare-icon.swift <input.png> <output.png>\n", stderr)
    exit(1)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fputs("Failed to load input image.\n", stderr)
    exit(1)
}

let width = image.width
let height = image.height
let bpp = 4
let bpr = width * bpp
var pixels = [UInt8](repeating: 0, count: height * bpr)

guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bpr,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else {
    fputs("Failed to create bitmap context.\n", stderr)
    exit(1)
}

ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

var minX = width
var minY = height
var maxX = 0
var maxY = 0
var found = false

for y in 0..<height {
    for x in 0..<width {
        let i = y * bpr + x * bpp
        let r = Double(pixels[i]) / 255.0
        let g = Double(pixels[i + 1]) / 255.0
        let b = Double(pixels[i + 2]) / 255.0
        let a = Double(pixels[i + 3]) / 255.0
        if a < 0.08 { continue }

        let maxC = max(r, max(g, b))
        let minC = min(r, min(g, b))
        let sat = maxC > 0.0001 ? (maxC - minC) / maxC : 0.0
        let isBlue = b > r + 0.05 && b > g + 0.03
        if isBlue && sat > 0.10 {
            found = true
            if x < minX { minX = x }
            if y < minY { minY = y }
            if x > maxX { maxX = x }
            if y > maxY { maxY = y }
        }
    }
}

let crop: CGRect
if found {
    var x = minX
    var y = minY
    var w = maxX - minX + 1
    var h = maxY - minY + 1

    // Tighten to tile and remove glow fringe.
    let pad = 4
    x = max(0, x + pad)
    y = max(0, y + pad)
    w = max(1, min(width - x, w - pad * 2))
    h = max(1, min(height - y, h - pad * 2))

    // Keep square framing around the tile.
    let side = max(w, h)
    let cx = x + w / 2
    let cy = y + h / 2
    var sx = cx - side / 2
    var sy = cy - side / 2
    sx = max(0, min(width - side, sx))
    sy = max(0, min(height - side, sy))
    crop = CGRect(x: sx, y: sy, width: side, height: side)
} else {
    let side = min(width, height)
    crop = CGRect(x: (width - side) / 2, y: (height - side) / 2, width: side, height: side)
}

guard let cropped = image.cropping(to: crop.integral) else {
    fputs("Failed to crop icon.\n", stderr)
    exit(1)
}

let out = 1024
let outBpr = out * bpp
var outPixels = [UInt8](repeating: 0, count: out * outBpr)

guard let outCtx = CGContext(
    data: &outPixels,
    width: out,
    height: out,
    bitsPerComponent: 8,
    bytesPerRow: outBpr,
    space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Failed to create output context.\n", stderr)
    exit(1)
}

outCtx.interpolationQuality = .high
outCtx.draw(cropped, in: CGRect(x: 0, y: 0, width: out, height: out))

// Remove any neutral/light surround connected to edges, preserving central blue tile + castle.
func isEdgeBackground(_ x: Int, _ y: Int) -> Bool {
    let i = y * outBpr + x * bpp
    let r = Double(outPixels[i]) / 255.0
    let g = Double(outPixels[i + 1]) / 255.0
    let b = Double(outPixels[i + 2]) / 255.0
    let a = Double(outPixels[i + 3]) / 255.0
    if a < 0.05 { return true }
    let maxC = max(r, max(g, b))
    let minC = min(r, min(g, b))
    let sat = maxC > 0.0001 ? (maxC - minC) / maxC : 0.0
    let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
    let blueDominant = b > r + 0.05 && b > g + 0.03
    // Edge background is mostly neutral/light and not blue-dominant.
    return !blueDominant && sat < 0.38 && luminance > 0.28
}

var visited = [UInt8](repeating: 0, count: out * out)
var queue: [(Int, Int)] = []
func enqueue(_ x: Int, _ y: Int) {
    let vi = y * out + x
    if visited[vi] == 1 { return }
    visited[vi] = 1
    queue.append((x, y))
}
for x in 0..<out {
    enqueue(x, 0)
    enqueue(x, out - 1)
}
for y in 0..<out {
    enqueue(0, y)
    enqueue(out - 1, y)
}
var head = 0
while head < queue.count {
    let (x, y) = queue[head]
    head += 1
    if !isEdgeBackground(x, y) { continue }
    let i = y * outBpr + x * bpp
    outPixels[i + 3] = 0
    if x > 0 { enqueue(x - 1, y) }
    if x + 1 < out { enqueue(x + 1, y) }
    if y > 0 { enqueue(x, y - 1) }
    if y + 1 < out { enqueue(x, y + 1) }
}

// Ensure icon is fully opaque so macOS does not place it on a gray app plate.
// Fill transparent edge pixels with a representative blue sampled from the artwork.
var blueSample = (r: UInt8(48), g: UInt8(170), b: UInt8(255))
for y in stride(from: out / 2, to: out, by: 4) {
    for x in stride(from: out / 4, to: out * 3 / 4, by: 4) {
        let i = y * outBpr + x * bpp
        let r = outPixels[i]
        let g = outPixels[i + 1]
        let b = outPixels[i + 2]
        let a = outPixels[i + 3]
        if a > 200 && Int(b) > Int(r) + 10 && Int(b) > Int(g) + 6 {
            blueSample = (r, g, b)
            break
        }
    }
}

for y in 0..<out {
    for x in 0..<out {
        let i = y * outBpr + x * bpp
        let a = outPixels[i + 3]
        if a < 250 {
            outPixels[i] = blueSample.r
            outPixels[i + 1] = blueSample.g
            outPixels[i + 2] = blueSample.b
            outPixels[i + 3] = 255
        }
    }
}

guard let outImage = outCtx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fputs("Failed to create output image destination.\n", stderr)
    exit(1)
}

CGImageDestinationAddImage(dest, outImage, nil)
if !CGImageDestinationFinalize(dest) {
    fputs("Failed to write output image.\n", stderr)
    exit(1)
}

print("Prepared icon -> \(outputURL.path)")
