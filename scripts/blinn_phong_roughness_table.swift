//
//  blinn_phong_roughness_table.swift
//  ToyFlightSimulator
//
//  Reproduces the numbers quoted in
//  research/claude/modelio_material_semantics_blinn_phong_2026-09-21.md:
//    - PBR roughness -> Blinn-Phong exponent and back, with Karis's approximation
//      ("Specular BRDF Reference", 2013): alpha = roughness^2, exponent = 2 / alpha^2 - 2.
//      Model I/O's MDLMaterial.h says the derivation is intended: "Specular power for
//      Blinn-Phong can be derived from the roughness property using an approximation."
//    - the highlight half-width for an exponent: the angle between the normal and the half
//      vector at which pow(N.H, exponent) has fallen to one half.
//    - how much a highlight adds at N.H = 0.95 for the strength the repo's MTL files carry
//      (Ks = 1) against the engine default 0.25, with the unnormalized lobe
//      Lighting::ShadeDirectionalBlinnPhong uses (specular = strength * pow(N.H, exponent)).
//
//  Usage:
//      swift scripts/blinn_phong_roughness_table.swift
//

import Foundation

/// Karis 2013: alpha = roughness², Blinn-Phong exponent = 2 / alpha² − 2 (= 2 / roughness⁴ − 2).
func blinnPhongExponent(fromRoughness roughness: Double) -> Double {
    let alpha = roughness * roughness
    return 2.0 / (alpha * alpha) - 2.0
}

/// The inverse: roughness = (2 / (exponent + 2))^(1/4).
func roughness(fromBlinnPhongExponent exponent: Double) -> Double {
    let alphaSquared = 2.0 / (exponent + 2.0)
    return pow(alphaSquared, 0.25)
}

/// Angle between N and H, in degrees, where pow(N·H, exponent) == 0.5.
func halfWidthDegrees(forExponent exponent: Double) -> Double {
    let cosine = pow(0.5, 1.0 / exponent)
    return acos(cosine) * 180.0 / .pi
}

print("PBR roughness -> Blinn-Phong exponent (Karis: 2 / roughness^4 - 2)")
for roughness in [0.0, 0.1, 0.3, 0.5, 0.7, 0.9, 1.0] {
    print(String(format: "  roughness %.2f -> exponent %.1f", roughness, blinnPhongExponent(fromRoughness: roughness)))
}

print("\nMTL Ns -> equivalent roughness (the repo's values; 32 is the engine default)")
for exponent in [10.0, 16.0, 32.0, 64.0, 80.0, 200.0, 225.0] {
    print(String(format: "  Ns %5.0f -> roughness %.3f", exponent, roughness(fromBlinnPhongExponent: exponent)))
}

print("\nHighlight half-width: angle between N and H where pow(N.H, Ns) falls to 0.5")
for exponent in [1.0, 2.0, 16.0, 32.0, 80.0, 225.0] {
    print(String(format: "  Ns %5.0f -> %.1f degrees", exponent, halfWidthDegrees(forExponent: exponent)))
}

print("\nSpecular added at N.H = 0.95 (sun radiance 1, specularIntensity 1): Ks = 1 vs the 0.25 default")
for exponent in [16.0, 32.0, 80.0] {
    let lobe = pow(0.95, exponent)
    print(String(format: "  Ns %5.0f: strength 1.0 adds %.3f, strength 0.25 adds %.3f", exponent, lobe, 0.25 * lobe))
}
