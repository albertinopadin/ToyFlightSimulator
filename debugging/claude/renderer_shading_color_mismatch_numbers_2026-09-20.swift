// Reproduces every number quoted in
// debugging/claude/renderer_shading_color_mismatch_2026-09-20.md.
// Run: swift renderer_shading_color_mismatch_numbers_2026-09-20.swift
import Foundation
import simd

func linearToSRGB(_ c: Float) -> Float {
    return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
}
func srgb8(_ v: SIMD3<Float>) -> String {
    let e = SIMD3<Float>(linearToSRGB(min(v.x, 1)), linearToSRGB(min(v.y, 1)), linearToSRGB(min(v.z, 1)))
    return String(format: "(%3.0f, %3.0f, %3.0f)", e.x * 255, e.y * 255, e.z * 255)
}
func lin(_ v: SIMD3<Float>) -> String {
    return String(format: "(%.3f, %.3f, %.3f)", v.x, v.y, v.z)
}

let groundAlbedo = SIMD3<Float>(0.3, 0.7, 0.1)          // GameScene.addGround default
let sunPosition  = SIMD3<Float>(0, 200, 4)              // FlightboxWithPhysics: jetPos.y + 100
let sunDirection = simd_normalize(sunPosition)          // LightObject.direction (derived from position)
print("sun direction (world, surface -> sun):", lin(sunDirection))

print("\n=== Current renderers, ground pixel (measured in the screenshots) ===")
let groundUp = SIMD3<Float>(0, 1, 0)
let nDotL = max(simd_dot(groundUp, sunDirection), 0)
print(String(format: "ground nDotL = %.4f", nDotL))

// OIT: material_fragment writes the raw base color.
print("OIT      expected linear", lin(groundAlbedo), "-> sRGB8", srgb8(groundAlbedo), " measured (149, 218, 89)")

// Tiled: CalculateDirectionalLighting = albedo * (1 - metallic) * nDotL * 1.0 * lightColor, then * shadow.
let metallic: Float = 0.1                               // material.shininess hardcoded in the tiled light pass
let tiledLit = groundAlbedo * (1 - metallic) * nDotL
let tiledShadowed = tiledLit * 0.5                      // CalculateShadow floor: 0.5 + 0.5 * 0
print("Tiled    lit      linear", lin(tiledLit), "-> sRGB8", srgb8(tiledLit), " measured (142, 208, 85)")
print("Tiled    shadowed linear", lin(tiledShadowed), "-> sRGB8", srgb8(tiledShadowed), " measured (103, 152, 61)")

// Single pass: the ground normal is NaN (see below) -> diffuse floor 0.4, specular 0, shadow 1.0.
let spGround = groundAlbedo * 0.4
print("SinglePs ground   linear", lin(spGround), "-> sRGB8", srgb8(spGround), " measured ( 96, 144, 56)")

print("\n=== Single pass: half-precision overflow of the ground normal ===")
let groundScale: Float = 1_000_000                      // FlightboxWithPhysics.groundSize
let scaledNormal = groundUp * groundScale               // normalMatrix * in.normal, normalMatrix carries the scale
let asHalf = SIMD3<Float16>(Float16(scaledNormal.x), Float16(scaledNormal.y), Float16(scaledNormal.z))
print("normalMatrix * normal (float):", scaledNormal)
print("converted to half3:           ", asHalf, "   (Float16.greatestFiniteMagnitude =", Float16.greatestFiniteMagnitude, ")")
let normalizedHalf = simd_normalize(SIMD3<Float>(Float(asHalf.x), Float(asHalf.y), Float(asHalf.z)))
print("normalize() in the fragment:  ", normalizedHalf)
print("max(dot(NaN, L), 0.4) = 0.4 and powr(max(dot(NaN,H),0),1) = 0 -> ground = 0.4 * albedo")

print("\n=== Single pass: specular exponent 1 blows out the jet ===")
let jetTopAlbedoOIT: Float = 0.578                      // measured OIT jet top, linear
let jetRatioNeededToClip = 1.0 / jetTopAlbedoOIT
print(String(format: "jet top albedo %.3f; diffuse(1.0) + specular >= %.2f * albedo clips to white; specular term needed >= %.2f * albedo",
             jetTopAlbedoOIT, jetRatioNeededToClip, jetRatioNeededToClip - 1))
// Cube front face, camera level, sun overhead: N = (0,0,-1), V = (0,0,-1), L = sunDirection
let faceN = SIMD3<Float>(0, 0, -1), faceV = SIMD3<Float>(0, 0, -1)
let H = simd_normalize(sunDirection + faceV)
let nDotH = max(simd_dot(faceN, H), 0)
print(String(format: "camera-facing vertical face: nDotH = %.3f; exponent 1 -> specular = %.3f * albedo; exponent 32 -> %.2e * albedo",
             nDotH, nDotH, pow(nDotH, 32)))
print(String(format: "  current single pass face brightness = floor 0.4 + specular %.3f = %.3f * albedo (top face ~ 1.0 + specular)", nDotH, 0.4 + nDotH))

print("\n=== OIT: why the commented-out GetPhongIntensity was 'very dark' ===")
let materialAmbient: Float = 0.1, materialDiffuse: Float = 1.0
let lightAmbient: Float = 0.4, lightDiffuse: Float = 0.5, brightness: Float = 1.0
let ambientTerm = materialAmbient * lightAmbient * brightness
print(String(format: "ambient term = material.ambient %.1f * light.ambientIntensity %.1f = %.2f (and only added on back faces)", materialAmbient, lightAmbient, ambientTerm))
for distance: Float in [0, 100, 500, 2000] {
    let fragment = SIMD3<Float>(distance, 0, 0)
    let toLight = simd_normalize(sunPosition - fragment)  // point-light style direction
    let n = max(simd_dot(groundUp, toLight), 0)
    let diffuseTerm = materialDiffuse * lightDiffuse * max(n, 0.3) * brightness
    print(String(format: "ground %5.0f m from origin: nDotL(point-style) = %.3f -> diffuse term = %.3f * albedo", distance, n, diffuseTerm))
}

print("\n=== Proposed shared model: ambient + shadow * (diffuse + specular) ===")
let kAmbient: Float = 0.3, kDiffuse: Float = 0.7, kSpecular: Float = 0.25, shininess: Float = 32
func shade(albedo: SIMD3<Float>, n: SIMD3<Float>, v: SIMD3<Float>, shadow: Float) -> SIMD3<Float> {
    let ndl = max(simd_dot(n, sunDirection), 0)
    let h = simd_normalize(sunDirection + v)
    let spec = kSpecular * pow(max(simd_dot(n, h), 0), shininess)
    let ambient = albedo * kAmbient
    let direct = albedo * kDiffuse * ndl + SIMD3<Float>(repeating: spec)
    return ambient + direct * shadow
}
let viewFromAbove = simd_normalize(SIMD3<Float>(0, 0.07, -1))   // camera ~4 deg above the ground ray
let litGround = shade(albedo: groundAlbedo, n: groundUp, v: viewFromAbove, shadow: 1)
let shadowedGround = shade(albedo: groundAlbedo, n: groundUp, v: viewFromAbove, shadow: 0)
let purple = SIMD3<Float>(0.5, 0, 0.5)
let purpleTop = shade(albedo: purple, n: groundUp, v: viewFromAbove, shadow: 1)
let purpleFace = shade(albedo: purple, n: faceN, v: faceV, shadow: 1)
print("ground lit      ", lin(litGround), "-> sRGB8", srgb8(litGround))
print("ground shadowed ", lin(shadowedGround), "-> sRGB8", srgb8(shadowedGround))
print("purple top      ", lin(purpleTop), "-> sRGB8", srgb8(purpleTop))
print("purple side     ", lin(purpleFace), "-> sRGB8", srgb8(purpleFace))
print(String(format: "sum ambient + diffuse = %.2f (<= 1 so a fully lit surface never clips)", kAmbient + kDiffuse))
// Specular highlight check: a sphere point whose normal is exactly the half vector
let highlightN = simd_normalize(sunDirection + viewFromAbove)
let highlight = shade(albedo: purple, n: highlightN, v: viewFromAbove, shadow: 1)
print("purple highlight peak (N == H)", lin(highlight), "-> sRGB8", srgb8(highlight))

// ---------------------------------------------------------------------------
// Added 2026-09-20 after cross-checking the Codex diagnosis
// (debugging/codex/renderer_shading_color_diagnosis_2026-09-20.md).
// ---------------------------------------------------------------------------

print("\n=== Baseline with the scene's EXISTING light values (ambient 0.4, diffuse 0.5), specular off ===")
func shadeBaseline(albedo: SIMD3<Float>, n: SIMD3<Float>, shadow: Float,
                   ambient: Float, diffuse: Float) -> SIMD3<Float> {
    let ndl = max(simd_dot(n, sunDirection), 0)
    return albedo * ambient + shadow * albedo * diffuse * ndl
}
for (label, albedo, n, shadow) in [("ground lit      ", groundAlbedo, groundUp, Float(1)),
                                   ("ground shadowed ", groundAlbedo, groundUp, Float(0)),
                                   ("purple top      ", purple, groundUp, Float(1)),
                                   ("purple side     ", purple, faceN, Float(1))] {
    let c = shadeBaseline(albedo: albedo, n: n, shadow: shadow, ambient: 0.4, diffuse: 0.5)
    print(label, lin(c), "-> sRGB8", srgb8(c))
}
print("gray 0.5 albedo, white sun, ambient 0.4, diffuse 0.5 (Codex table, re-derived):")
for (cosine, visibility) in [(Float(0), Float(1)), (0.5, 1), (1, 1), (1, 0)] {
    let oldTiled = 0.5 * 0.9 * cosine * (0.5 + 0.5 * visibility)
    let proposed = 0.5 * 0.4 + visibility * 0.5 * 0.5 * cosine
    print(String(format: "  cosine %.1f visibility %.0f: old tiled %.3f, proposed %.3f (sRGB %.4f)",
                 cosine, visibility, oldTiled, proposed, linearToSRGB(proposed)))
}

print("\n=== Mixed-frame dot product (single pass 2c): world normal vs eye-space light ===")
for degrees: Float in [0, 4, 30, 60, 90] {
    let r = degrees * .pi / 180
    // rotate the light about X by the camera pitch; the stored normal is NOT rotated
    let lightEye = SIMD3<Float>(0, cos(r), sin(r))
    let mixed = simd_dot(groundUp, lightEye)
    print(String(format: "  camera pitched %2.0f deg: correct N.L = 1.000, mixed-frame N.L = %.3f%@",
                 degrees, mixed, mixed < 0.4 ? "  -> below the 0.4 floor" : ""))
}

print("\n=== sRGB-encoded palette components treated as linear (RandomColor.swift) ===")
func srgbToLinear(_ c: Float) -> Float { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
print(String(format: "  NSColor.purple component 0.5 (sRGB) -> linear %.3f; the engine shows linear 0.5 as sRGB %.3f",
             srgbToLinear(0.5), linearToSRGB(0.5)))

print("\n=== Nonuniform scale and the upper-left 3x3 normal matrix (Codex 7.3, re-derived) ===")
let scaleXYZ = SIMD3<Float>(2, 1, 1)
let localNormal = simd_normalize(SIMD3<Float>(1, 1, 0))
let localTangent = simd_normalize(SIMD3<Float>(1, -1, 0))
let currentNormal = simd_normalize(scaleXYZ * localNormal)          // upper-left 3x3 = the scale itself
let correctNormal = simd_normalize(localNormal / scaleXYZ)          // inverse transpose of a diagonal scale
let worldTangent = simd_normalize(scaleXYZ * localTangent)
print("  current normal", lin(currentNormal), "dot(tangent) =", String(format: "%.3f", simd_dot(currentNormal, worldTangent)))
print("  correct normal", lin(correctNormal), "dot(tangent) =", String(format: "%.3f", simd_dot(correctNormal, worldTangent)))

print("\n=== Transparency compositing check (light first, premultiply once) ===")
let straightLit: Float = 0.6, opacity: Float = 0.5, background: Float = 0.2
print(String(format: "  0.6 lit at opacity 0.5 over 0.2 = %.3f (expected 0.400)", straightLit * opacity + (1 - opacity) * background))
print(String(format: "  0.8^1 = %.3f, 0.8^32 = %.6f, pow(x, 0) = %.1f", pow(0.8 as Float, 1), pow(0.8 as Float, 32), pow(0.8 as Float, 0)))
