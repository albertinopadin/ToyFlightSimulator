//
//  RandomColor.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/17/26.
//

import simd

#if os(macOS)
import AppKit
typealias TFSColor = NSColor
#else
import UIKit
typealias TFSColor = UIColor
#endif

/// Shared palette used by scenes that want to scatter colorful objects.
/// Sampled by `randomPaletteColor()`.
let colors: [TFSColor] = [
    .blue,
    .black,
    .brown,
    .cyan,
    .darkGray,
    .gray,
    .green,
    .lightGray,
    .magenta,
    .orange,
    .purple,
    .red,
    .systemRed,
    .systemBlue,
    .systemPink,
    .systemTeal,
    .systemGreen,
    .systemCyan,
    .systemMint,
    .systemIndigo,
    .systemYellow,
    .white,
    .yellow
]

/// Returns a random RGBA color (float4) sampled from `colors`. Falls back to
/// `fallback` when the sampled color lives in a monochrome color space and
/// therefore has no RGB components to extract.
func randomPaletteColor(fallback: float4 = [0.5, 0.5, 0.5, 1.0]) -> float4 {
    let cg = colors.randomElement()!.cgColor
    guard cg.colorSpace?.model != .monochrome,
          let components = cg.components else {
        return fallback
    }
    return float4(x: Float(components[0]),
                  y: Float(components[1]),
                  z: Float(components[2]),
                  w: Float(components[3]))
}
