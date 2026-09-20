// Samples pixel values from the three renderer screenshots so the shader
// analysis can be checked against measured output instead of eyeballing.
// Usage: swift renderer_shading_color_mismatch_sample_pixels_2026-09-20.swift <png path> x1,y1 x2,y2 ...
// Coordinates are in ORIGINAL image pixels. Prints sRGB 8-bit and the
// linear (decoded) value for each sample, averaged over a 5x5 box.
import Foundation
import CoreGraphics
import ImageIO

func srgbToLinear(_ c: Double) -> Double {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: sample_pixels.swift <png> x,y [x,y ...]")
    exit(1)
}
let url = URL(fileURLWithPath: args[1])
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    print("could not load \(args[1])")
    exit(1)
}
let width = image.width
let height = image.height
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bytesPerRow = width * 4
var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: bytesPerRow, space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

print("image \(width)x\(height)")
for arg in args[2...] {
    let parts = arg.split(separator: ",").compactMap { Int($0) }
    guard parts.count == 2 else { continue }
    let cx = parts[0], cy = parts[1]
    var sum = [0.0, 0.0, 0.0]
    var n = 0.0
    for dy in -2...2 {
        for dx in -2...2 {
            let x = cx + dx, y = cy + dy
            guard x >= 0, y >= 0, x < width, y < height else { continue }
            let i = y * bytesPerRow + x * 4
            sum[0] += Double(pixels[i]); sum[1] += Double(pixels[i+1]); sum[2] += Double(pixels[i+2])
            n += 1
        }
    }
    let r = sum[0]/n, g = sum[1]/n, b = sum[2]/n
    let lr = srgbToLinear(r/255), lg = srgbToLinear(g/255), lb = srgbToLinear(b/255)
    print(String(format: "(%4d,%4d) sRGB8 = (%5.1f, %5.1f, %5.1f)  sRGB = (%.3f, %.3f, %.3f)  linear = (%.3f, %.3f, %.3f)",
                 cx, cy, r, g, b, r/255, g/255, b/255, lr, lg, lb))
}
