//
//  verify_center_of_mass_math.swift
//  ToyFlightSimulator
//
//  Self-checking verification of the matrix math behind center-of-mass recentering, and of
//  every derived number in plans/claude/aircraft_center_of_mass_recentering_2026-09-25.md.
//  Each check prints PASS or FAIL with the expected and actual values; INFO lines report facts
//  that are not pass/fail. The script exits with status 1 if any check fails.
//
//  What it covers:
//    A. The bake convention. Mesh.transformMeshBasis multiplies points as ROW vectors
//       (p * B), so a translation must sit in the bottom row (the w of columns 0-2).
//       Transform.translationMatrix is the column-vector form and the bake silently drops it.
//    B. Composition order: S * B0 * T_row(-c) puts c in engine meters and engine axes; the
//       reverse order reads c in native file units and axes.
//    C. composeImportTransform, the plan's pure helper: its edge cases.
//    D. The worked examples and milestone numbers (F-18, F-35, Sketchfab F-22).
//    E. Conjugation: Skeleton and TransformComponent map native joint and node deltas J into
//       the engine as B^T * J * (B^T)^-1. That stays exact for a translation-bearing B, and a
//       skeleton given B WITHOUT the translation misplaces vertices by (I - R) * c.
//    F. Whether B^T * I * (B^T)^-1 is bit-exactly identity (DrawManager's `!= .identity` path).
//    G. SingleMeshVertexMetadata.transformingCentroid (p * B, w = 1) carries the translation.
//    H. The translation changes neither the winding determinant nor the meterized length.
//
//  Inputs: the import-frame measurements (nose tips, nozzle centers, wheel positions) are
//  copied from `swift scripts/measure_center_of_mass.swift`. If a model or its registration
//  changes, re-run that script and update the `Measured` values below.
//
//  The helpers `rowVectorTranslationMatrix` and `composeImportTransform` are the reference
//  behavior for the engine versions the plan specifies (Transform.swift, Model.swift). Keep
//  them identical. The other helpers mirror existing engine code (named at each one).
//
//  Usage (no arguments; runs anywhere):
//      swift scripts/verify_center_of_mass_math.swift
//

import Foundation
import simd

// MARK: - Measured inputs (import-frame meters, from measure_center_of_mass.swift)

enum Measured {
    // F/A-18 (FA-18F.obj; basis rotate180AroundY; not meterized)
    static let f18NoseTip = SIMD3<Float>(0, 1.418, 9.085)
    static let f18NozzleCenter = SIMD3<Float>(0, 2.205, -7.648)     // part EngineNozzles_Paint
    static let f18LowestVertexY: Float = -0.011
    static let f18MainWheelsZ: Float = -2.490
    static let f18NoseWheelZ: Float = 3.585
    static let f18CameraOffset = SIMD3<Float>(0, 9, -20)             // F18.cameraOffset

    // F-35 (F-35A_Lightning_II.usdz; identity basis; meterization scale below)
    static let f35MeterizationScale: Float = 0.5431731
    static let f35NoseTip = SIMD3<Float>(0, 0.918, 7.835)
    static let f35NozzleCenter = SIMD3<Float>(-0.004, 1.063, -5.524)  // part Object_3
    static let f35CameraOffset = SIMD3<Float>(0, 6, -18)             // F35.cameraOffset

    // Sketchfab F-22 (F-22_Raptor.usdz; basis transformYMinusZXToXYZ; meterization scale below)
    static let sketchfabF22MeterizationScale: Float = 0.0996041
    static let sketchfabF22NoseTip = SIMD3<Float>(0, -0.052, 13.489)
    static let sketchfabF22NozzleCenter = SIMD3<Float>(0, 0.000, -3.173)  // region box, nozzle pair
    static let sketchfabF22MainWheelsZ: Float = 1.785
    static let sketchfabF22NoseWheelZ: Float = 7.849
    static let sketchfabF22CameraOffset = SIMD3<Float>(0, 7, -20)    // F22.cameraOffset
    static let sketchfabF22AfterburnerLeft = SIMD3<Float>(-0.600, 0.098, -4)  // F22.init

    // CGTrader F-22 meterization scale (composition-order example only)
    static let cgtraderF22MeterizationScale: Float = 2.1961696
}

/// The nose-wheel load share the plan adopts (Raymer's 8-15 %, middle of the range).
let targetNoseWheelShare: Float = 0.12

// MARK: - Engine mirrors and plan helpers

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3<Float>(x, y, z) }
}

/// Mirrors `Transform.translationMatrix`: column-vector form, translation in column 3.
func translationMatrix(_ translation: SIMD3<Float>) -> float4x4 {
    float4x4(SIMD4<Float>(1, 0, 0, 0), SIMD4<Float>(0, 1, 0, 0), SIMD4<Float>(0, 0, 1, 0), SIMD4<Float>(translation, 1))
}

/// Mirrors `Transform.scaleMatrix` for a uniform scale.
func uniformScaleMatrix(_ scale: Float) -> float4x4 {
    float4x4(diagonal: SIMD4<Float>(scale, scale, scale, 1))
}

/// Rotation about a unit axis, column-vector convention (for joint deltas).
func rotationMatrix(radians: Float, axis: SIMD3<Float>) -> float4x4 {
    float4x4(simd_quatf(angle: radians, axis: simd_normalize(axis)))
}

/// Transform.rotationMatrix(radians: pi, axis: Y_AXIS), with its exact entries: F-16 / F-18.
let rotate180AroundY = float4x4(SIMD4<Float>(-1, 0, 0, 0), SIMD4<Float>(0, 1, 0, 0),
                                SIMD4<Float>(0, 0, -1, 0), SIMD4<Float>(0, 0, 0, 1))
/// Transform.transformXMinusZYToXYZ: CGTrader F-22.
let transformXMinusZYToXYZ = float4x4(SIMD4<Float>(1, 0, 0, 0), SIMD4<Float>(0, 0, 1, 0),
                                      SIMD4<Float>(0, -1, 0, 0), SIMD4<Float>(0, 0, 0, 1))
/// Transform.transformYMinusZXToXYZ: Sketchfab F-22.
let transformYMinusZXToXYZ = float4x4(SIMD4<Float>(0, 1, 0, 0), SIMD4<Float>(0, 0, -1, 0),
                                      SIMD4<Float>(1, 0, 0, 0), SIMD4<Float>(0, 0, 0, 1))

/// PLAN HELPER (Transform.rowVectorTranslationMatrix): the translation in the bake's row-vector
/// form. The offset goes in the w of columns 0-2; it equals transpose(translationMatrix(offset)).
func rowVectorTranslationMatrix(_ offset: SIMD3<Float>) -> float4x4 {
    var matrix = matrix_identity_float4x4
    matrix.columns.0.w = offset.x
    matrix.columns.1.w = offset.y
    matrix.columns.2.w = offset.z
    return matrix
}

/// PLAN HELPER (Model.ComposeImportTransform): the one matrix the importer bakes. Row-vector,
/// so the leftmost factor applies first: meterization scale, then the basis, then recentering.
func composeImportTransform(basisTransform: float4x4?, meterizationScale: Float?,
                            centerOfMassInImportFrame: SIMD3<Float>?) -> float4x4? {
    if basisTransform == nil && meterizationScale == nil && centerOfMassInImportFrame == nil {
        return nil
    }
    var importTransform = basisTransform ?? matrix_identity_float4x4
    if let meterizationScale {
        importTransform = uniformScaleMatrix(meterizationScale) * importTransform
    }
    if let centerOfMassInImportFrame {
        importTransform = importTransform * rowVectorTranslationMatrix(-centerOfMassInImportFrame)
    }
    return importTransform
}

/// Mirrors `Mesh.transformMeshBasis` for a point (w = 1).
func bakePoint(_ point: SIMD3<Float>, _ transform: float4x4) -> SIMD3<Float> {
    simd_mul(SIMD4<Float>(point, 1), transform).xyz
}

/// Mirrors `Mesh.transformMeshBasis` for a normal, tangent or bitangent (w = 0).
func bakeDirection(_ direction: SIMD3<Float>, _ transform: float4x4) -> SIMD3<Float> {
    simd_mul(SIMD4<Float>(direction, 0), transform).xyz
}

/// Mirrors `Transform.basisConjugationMatrices`: (B^T, (B^T)^-1).
func basisConjugationMatrices(for basisTransform: float4x4) -> (left: float4x4, right: float4x4) {
    let transposed = basisTransform.transpose
    return (transposed, transposed.inverse)
}

/// Mirrors the private `det3x3` in ModelMeterizationTests and the winding check in Mesh.
func determinantOfLinearPart(_ matrix: float4x4) -> Float {
    simd_determinant(simd_float3x3(matrix.columns.0.xyz, matrix.columns.1.xyz, matrix.columns.2.xyz))
}

/// Mirrors `Model.GetLengthAxisExtent` (w = 0: an extent is a size, not a point).
func lengthAxisExtent(_ nativeExtent: SIMD3<Float>, _ transform: float4x4) -> Float {
    abs(simd_mul(SIMD4<Float>(nativeExtent, 0), transform).z)
}

/// Import-frame point back to native coordinates, by inverting the (invertible) import transform.
func nativePoint(fromImport importPoint: SIMD3<Float>, basis: float4x4, meterizationScale: Float) -> SIMD3<Float> {
    bakePoint(importPoint, (uniformScaleMatrix(meterizationScale) * basis).inverse)
}

/// Plan Milestone 4: height of the straight nose->nozzle line at a station.
func noseToNozzleLineHeight(noseTip: SIMD3<Float>, nozzleCenter: SIMD3<Float>, atStationZ stationZ: Float) -> Float {
    let fractionFromNose = (noseTip.z - stationZ) / (noseTip.z - nozzleCenter.z)
    return noseTip.y + fractionFromNose * (nozzleCenter.y - noseTip.y)
}

/// Plan Milestone 6: static balance on a tricycle gear, moments about the main-wheel line.
func centerOfMassStationForNoseShare(noseGearZ: Float, mainGearZ: Float, noseLoadShare: Float) -> Float {
    mainGearZ + noseLoadShare * (noseGearZ - mainGearZ)
}

/// SplitMix64, as in ToyFlightSimulatorTests/TestSupport/SeededRandom.swift: reproducible runs.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Check reporting

var failureCount = 0

func fmt(_ v: SIMD3<Float>) -> String { String(format: "(%.4f, %.4f, %.4f)", v.x, v.y, v.z) }

func check(_ name: String, _ actual: SIMD3<Float>, _ expected: SIMD3<Float>, tolerance: Float = 1e-3) {
    let passed = simd_length(actual - expected) <= tolerance
    if !passed { failureCount += 1 }
    print("  \(passed ? "PASS" : "FAIL")  \(name): \(fmt(actual))" + (passed ? "" : "   expected \(fmt(expected))"))
}

func check(_ name: String, _ actual: Float, _ expected: Float, tolerance: Float = 1e-3) {
    let passed = abs(actual - expected) <= tolerance
    if !passed { failureCount += 1 }
    print("  \(passed ? "PASS" : "FAIL")  \(name): \(String(format: "%.4f", actual))"
          + (passed ? "" : String(format: "   expected %.4f", expected)))
}

func check(_ name: String, _ condition: Bool, detail: String = "") {
    if !condition { failureCount += 1 }
    print("  \(condition ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : ": \(detail)")")
}

func info(_ text: String) {
    print("  INFO  \(text)")
}

// MARK: - A. The bake convention

print("A. Row-vector bake: where a translation must live")
let samplePoint = SIMD3<Float>(1, 2, 3)
let f18StationZeroCenterOfMass = SIMD3<Float>(0, 1.845, 0)   // Milestone 5 value
let bakedWithoutTranslation = bakePoint(samplePoint, rotate180AroundY)
check("column-form translation AFTER the basis is dropped",
      bakePoint(samplePoint, rotate180AroundY * translationMatrix(-f18StationZeroCenterOfMass)), bakedWithoutTranslation)
check("column-form translation BEFORE the basis is dropped",
      bakePoint(samplePoint, translationMatrix(-f18StationZeroCenterOfMass) * rotate180AroundY), bakedWithoutTranslation)
info(String(format: "where it went: output w = %.3f (the offset leaked into w, which .xyz discards)",
            simd_mul(SIMD4<Float>(samplePoint, 1), rotate180AroundY * translationMatrix(-f18StationZeroCenterOfMass)).w))
check("row-form translation moves the point",
      bakePoint(samplePoint, rotate180AroundY * rowVectorTranslationMatrix(-f18StationZeroCenterOfMass)), SIMD3<Float>(-1, 0.155, -3))
check("row-form translation leaves directions (w = 0) alone",
      bakeDirection(SIMD3<Float>(0, 1, 0), rotate180AroundY * rowVectorTranslationMatrix(-f18StationZeroCenterOfMass)), SIMD3<Float>(0, 1, 0))
check("rowVectorTranslationMatrix(t) == transpose(translationMatrix(t))",
      rowVectorTranslationMatrix([0.5, -1.25, 2]) == translationMatrix([0.5, -1.25, 2]).transpose)

// MARK: - B. Composition order

print("\nB. Composition order (CGTrader basis, s = \(Measured.cgtraderF22MeterizationScale), c = (0, 1, 0))")
let exampleCenterOfMass = SIMD3<Float>(0, 1, 0)
let cgtraderMeterized = uniformScaleMatrix(Measured.cgtraderF22MeterizationScale) * transformXMinusZYToXYZ
check("S * B0 * T_row(-c): c subtracted in engine meters and axes",
      bakePoint(samplePoint, cgtraderMeterized * rowVectorTranslationMatrix(-exampleCenterOfMass)),
      SIMD3<Float>(2.1961696, 5.5885086, -4.392339))
check("T_row(-c) * S * B0: c read in native units and axes (the wrong order)",
      bakePoint(samplePoint, rowVectorTranslationMatrix(-exampleCenterOfMass) * cgtraderMeterized),
      SIMD3<Float>(2.1961696, 6.5885086, -2.1961696))

// MARK: - C. composeImportTransform edge cases

print("\nC. composeImportTransform edge cases")
check("all inputs absent returns nil (Mesh.init then skips the vertex pass)",
      composeImportTransform(basisTransform: nil, meterizationScale: nil, centerOfMassInImportFrame: nil) == nil)
if let centerOfMassOnly = composeImportTransform(basisTransform: nil, meterizationScale: nil, centerOfMassInImportFrame: [0, 1, 0]) {
    check("center of mass alone still bakes (moves points by -c)", bakePoint(samplePoint, centerOfMassOnly), SIMD3<Float>(1, 1, 3))
} else {
    check("center of mass alone still bakes (moves points by -c)", false, detail: "returned nil")
}
check("c = 0 gives exactly the matrix without c",
      composeImportTransform(basisTransform: rotate180AroundY, meterizationScale: 2, centerOfMassInImportFrame: .zero)
      == composeImportTransform(basisTransform: rotate180AroundY, meterizationScale: 2, centerOfMassInImportFrame: nil))

// MARK: - D. Worked examples and milestone numbers

print("\nD1. F-18, Milestone 5 (station 0): the plan's worked example")
let f18LineAtZero = noseToNozzleLineHeight(noseTip: Measured.f18NoseTip, nozzleCenter: Measured.f18NozzleCenter, atStationZ: 0)
check("nose->nozzle line height at z = 0", f18LineAtZero, 1.845)
info(String(format: "line tilt from body +Z: %.2f deg nose-down",
            atan2(Measured.f18NozzleCenter.y - Measured.f18NoseTip.y, Measured.f18NoseTip.z - Measured.f18NozzleCenter.z) * 180 / .pi))
let f18StationZeroTransform = composeImportTransform(basisTransform: rotate180AroundY, meterizationScale: nil,
                                                     centerOfMassInImportFrame: f18StationZeroCenterOfMass)!
check("import transform keeps the offset in column1.w", f18StationZeroTransform.columns.1.w, -1.845)
check("nose tip, native -> body", bakePoint(nativePoint(fromImport: Measured.f18NoseTip, basis: rotate180AroundY, meterizationScale: 1),
                                            f18StationZeroTransform), SIMD3<Float>(0, -0.427, 9.085))
check("nozzle center, native -> body", bakePoint(nativePoint(fromImport: Measured.f18NozzleCenter, basis: rotate180AroundY, meterizationScale: 1),
                                                 f18StationZeroTransform), SIMD3<Float>(0, 0.360, -7.648))
check("lowest vertex y, body", Measured.f18LowestVertexY - f18StationZeroCenterOfMass.y, -1.856)
check("90-deg roll swing of the centerline point today (r * sqrt 2)", f18StationZeroCenterOfMass.y * sqrt(2), 2.609)
check("90-deg roll swing of the nozzle center, today", Measured.f18NozzleCenter.y * sqrt(2), 3.118)
check("90-deg roll swing of the nozzle center, after", (Measured.f18NozzleCenter.y - f18StationZeroCenterOfMass.y) * sqrt(2), 0.509)
check("F18.cameraOffset re-expressed", Measured.f18CameraOffset - f18StationZeroCenterOfMass, SIMD3<Float>(0, 7.155, -20))
check("wheels above the runway on the legacy 2 m sphere, after", 2 + Measured.f18LowestVertexY - f18StationZeroCenterOfMass.y, 0.144)

print("\nD2. F-35, Milestone 4")
let f35CenterOfMass = SIMD3<Float>(0, noseToNozzleLineHeight(noseTip: Measured.f35NoseTip, nozzleCenter: Measured.f35NozzleCenter,
                                                             atStationZ: 0), 0)
check("nose->nozzle line height at z = 0", f35CenterOfMass.y, 1.003)
let f35Transform = composeImportTransform(basisTransform: nil, meterizationScale: Measured.f35MeterizationScale,
                                          centerOfMassInImportFrame: [0, 1.003, 0])!
let f35NativeNoseTip = nativePoint(fromImport: Measured.f35NoseTip, basis: matrix_identity_float4x4, meterizationScale: Measured.f35MeterizationScale)
let f35NativeNozzle = nativePoint(fromImport: Measured.f35NozzleCenter, basis: matrix_identity_float4x4, meterizationScale: Measured.f35MeterizationScale)
check("native nose tip (test input)", f35NativeNoseTip, SIMD3<Float>(0, 1.690069, 14.4245))
check("native nozzle center (test input)", f35NativeNozzle, SIMD3<Float>(-0.0073641, 1.9570189, -10.169871))
check("nose tip, native -> body", bakePoint(f35NativeNoseTip, f35Transform), SIMD3<Float>(0, -0.085, 7.835))
check("nozzle center, native -> body", bakePoint(f35NativeNozzle, f35Transform), SIMD3<Float>(-0.004, 0.060, -5.524))
check("F35.cameraOffset re-expressed", Measured.f35CameraOffset - SIMD3<Float>(0, 1.003, 0), SIMD3<Float>(0, 4.997, -18))
check("90-deg roll swing of the centerline point today", 1.003 * sqrt(2), 1.418)

print("\nD3. F-18, Milestone 6 (station from the 12 % nose-wheel share)")
let f18Wheelbase = Measured.f18NoseWheelZ - Measured.f18MainWheelsZ
check("wheelbase", f18Wheelbase, 6.075)
check("nose-wheel share if the CoM stayed at the origin", (0 - Measured.f18MainWheelsZ) / f18Wheelbase, 0.410)
let f18Station = centerOfMassStationForNoseShare(noseGearZ: Measured.f18NoseWheelZ, mainGearZ: Measured.f18MainWheelsZ,
                                                 noseLoadShare: targetNoseWheelShare)
check("station for 12 %", f18Station, -1.761)
let f18FinalCenterOfMass = SIMD3<Float>(0, noseToNozzleLineHeight(noseTip: Measured.f18NoseTip, nozzleCenter: Measured.f18NozzleCenter,
                                                                  atStationZ: f18Station), f18Station)
check("final c", f18FinalCenterOfMass, SIMD3<Float>(0, 1.928, -1.761))
let f18FinalTransform = composeImportTransform(basisTransform: rotate180AroundY, meterizationScale: nil,
                                               centerOfMassInImportFrame: [0, 1.928, -1.761])!
check("nose tip, native -> body", bakePoint(nativePoint(fromImport: Measured.f18NoseTip, basis: rotate180AroundY, meterizationScale: 1),
                                            f18FinalTransform), SIMD3<Float>(0, -0.510, 10.846))
check("nozzle center, native -> body", bakePoint(nativePoint(fromImport: Measured.f18NozzleCenter, basis: rotate180AroundY, meterizationScale: 1),
                                                 f18FinalTransform), SIMD3<Float>(0, 0.277, -5.887))
check("F18.cameraOffset re-expressed", Measured.f18CameraOffset - SIMD3<Float>(0, 1.928, -1.761), SIMD3<Float>(0, 7.072, -18.239))
check("wheels above the runway on the legacy 2 m sphere", 2 + Measured.f18LowestVertexY - 1.928, 0.061)

print("\nD4. Sketchfab F-22, Milestone 6")
let f22Wheelbase = Measured.sketchfabF22NoseWheelZ - Measured.sketchfabF22MainWheelsZ
check("wheelbase", f22Wheelbase, 6.064)
check("nose-wheel share if the CoM stayed at the origin (negative: origin behind the mains)",
      (0 - Measured.sketchfabF22MainWheelsZ) / f22Wheelbase, -0.294)
let f22Station = centerOfMassStationForNoseShare(noseGearZ: Measured.sketchfabF22NoseWheelZ, mainGearZ: Measured.sketchfabF22MainWheelsZ,
                                                 noseLoadShare: targetNoseWheelShare)
check("station for 12 %", f22Station, 2.512)
let f22FinalCenterOfMass = SIMD3<Float>(0, noseToNozzleLineHeight(noseTip: Measured.sketchfabF22NoseTip,
                                                                  nozzleCenter: Measured.sketchfabF22NozzleCenter,
                                                                  atStationZ: f22Station), f22Station)
check("final c", f22FinalCenterOfMass, SIMD3<Float>(0, -0.018, 2.512))
let f22PlanCenterOfMass = SIMD3<Float>(0, -0.018, 2.512)
let f22FinalTransform = composeImportTransform(basisTransform: transformYMinusZXToXYZ,
                                               meterizationScale: Measured.sketchfabF22MeterizationScale,
                                               centerOfMassInImportFrame: f22PlanCenterOfMass)!
let f22NativeNoseTip = nativePoint(fromImport: Measured.sketchfabF22NoseTip, basis: transformYMinusZXToXYZ,
                                   meterizationScale: Measured.sketchfabF22MeterizationScale)
let f22NativeNozzle = nativePoint(fromImport: Measured.sketchfabF22NozzleCenter, basis: transformYMinusZXToXYZ,
                                  meterizationScale: Measured.sketchfabF22MeterizationScale)
check("native nose tip (test input)", f22NativeNoseTip, SIMD3<Float>(135.4261, 0, 0.5221), tolerance: 1e-2)
check("native nozzle-pair center (test input)", f22NativeNozzle, SIMD3<Float>(-31.8565, 0, 0), tolerance: 1e-2)
check("nose tip, native -> body", bakePoint(f22NativeNoseTip, f22FinalTransform), SIMD3<Float>(0, -0.034, 10.977))
check("nozzle-pair center, native -> body", bakePoint(f22NativeNozzle, f22FinalTransform), SIMD3<Float>(0, 0.018, -5.685))
check("F22.cameraOffset re-expressed", Measured.sketchfabF22CameraOffset - f22PlanCenterOfMass, SIMD3<Float>(0, 7.018, -22.512))
check("F22 left afterburner re-expressed", Measured.sketchfabF22AfterburnerLeft - f22PlanCenterOfMass, SIMD3<Float>(-0.600, 0.116, -6.512))
info(String(format: "the two F-22 models agree: the 12 %% rule puts the CoM %.3f m behind the nose tip here, and "
            + "10.831 m on the CGTrader mesh's own wheels (its authored origin: 10.124 m)",
            Measured.sketchfabF22NoseTip.z - f22Station))

// MARK: - E. Conjugation with a translation-bearing basis

print("\nE. Conjugation B^T * J * (B^T)^-1 (Skeleton, TransformComponent)")
var generator = SplitMix64(state: 0x5EED_C0FF_EE12_3456)
func randomUnit() -> Float { Float.random(in: -1 ... 1, using: &generator) }

let transformsUnderTest: [(name: String, full: float4x4, withoutTranslation: float4x4)] = [
    ("F-18 final", f18FinalTransform, rotate180AroundY),
    ("F-35", f35Transform, uniformScaleMatrix(Measured.f35MeterizationScale)),
    ("Sketchfab F-22 final", f22FinalTransform,
     uniformScaleMatrix(Measured.sketchfabF22MeterizationScale) * transformYMinusZXToXYZ),
    ("CGTrader-like, off-axis c", cgtraderMeterized * rowVectorTranslationMatrix(-SIMD3<Float>(0.1, -0.7, 0.4)), cgtraderMeterized),
]
for transform in transformsUnderTest {
    var worstError: Float = 0
    var worstErrorWithoutTranslation: Float = 0
    let (left, right) = basisConjugationMatrices(for: transform.full)
    let (staleLeft, staleRight) = basisConjugationMatrices(for: transform.withoutTranslation)
    // Native-space scale of the samples: ~10 m in the body frame whatever the meterization.
    let nativeSpan: Float = 10 / cbrt(abs(determinantOfLinearPart(transform.full)))   // |det| = s^3
    for _ in 0..<2000 {
        let jointDelta = translationMatrix(SIMD3<Float>(randomUnit(), randomUnit(), randomUnit()) * nativeSpan * 0.3)
            * rotationMatrix(radians: randomUnit() * .pi, axis: SIMD3<Float>(randomUnit(), randomUnit(), randomUnit() + 1.5))
        let nativeVertex = SIMD3<Float>(randomUnit(), randomUnit(), randomUnit()) * nativeSpan
        // Truth: skin in the native frame, then bake.
        let truth = bakePoint(simd_mul(jointDelta, SIMD4<Float>(nativeVertex, 1)).xyz, transform.full)
        // What the shader does: the conjugated delta applied to the baked vertex.
        let bakedVertex = SIMD4<Float>(bakePoint(nativeVertex, transform.full), 1)
        worstError = max(worstError, simd_length(truth - simd_mul(left * jointDelta * right, bakedVertex).xyz))
        worstErrorWithoutTranslation = max(worstErrorWithoutTranslation,
                                           simd_length(truth - simd_mul(staleLeft * jointDelta * staleRight, bakedVertex).xyz))
    }
    check("\(transform.name): conjugation exact within 1e-4 m (2,000 random deltas)", worstError <= 1e-4,
          detail: String(format: "worst %.2e m; a skeleton given the basis WITHOUT the translation: worst %.3f m",
                         worstError, worstErrorWithoutTranslation))
}
let quarterTurnAboutX = rotationMatrix(radians: .pi / 2, axis: [1, 0, 0])
check("stale-basis error for a 90-deg joint rotation about X, c = (0, 1.845, 0): |(I - R) c|",
      simd_length(f18StationZeroCenterOfMass - simd_mul(quarterTurnAboutX, SIMD4<Float>(f18StationZeroCenterOfMass, 0)).xyz), 2.609)

// MARK: - F. Identity node transforms under conjugation

print("\nF. Is B^T * I * (B^T)^-1 bit-exactly identity? (DrawManager tests `localTransform != .identity`)")
for transform in transformsUnderTest {
    let (left, right) = basisConjugationMatrices(for: transform.full)
    let conjugatedIdentity = left * matrix_identity_float4x4 * right
    var largestDifference: Float = 0
    for column in 0..<4 {
        largestDifference = max(largestDifference, simd_length(conjugatedIdentity[column] - matrix_identity_float4x4[column]))
    }
    info("\(transform.name): " + (conjugatedIdentity == matrix_identity_float4x4
         ? "exact" : String(format: "not exact (largest difference %.2e): a static mesh would take the animated path", largestDifference)))
}
info("only the F-35 has animated node transforms among the recentered aircraft (the F-18 is an OBJ, "
     + "the Sketchfab F-22's time range is empty), so only its line matters")

// MARK: - G. Submesh centroids

print("\nG. SingleMeshVertexMetadata.transformingCentroid (p * B, w = 1)")
let nativeAileronCentroid = SIMD3<Float>(-5.462, 2.084, 3.773)
check("centroid with the Milestone 5 F-18 transform", bakePoint(nativeAileronCentroid, f18StationZeroTransform), SIMD3<Float>(5.462, 0.239, -3.773))
check("centroid with the Milestone 6 F-18 transform", bakePoint(nativeAileronCentroid, f18FinalTransform), SIMD3<Float>(5.462, 0.156, -2.012))
check("centroid without recentering (today)", bakePoint(nativeAileronCentroid, rotate180AroundY), SIMD3<Float>(5.462, 2.084, -3.773))

// MARK: - H. Winding and length

print("\nH. The translation changes neither the winding decision nor the meterized length")
let cgtraderRecentered = cgtraderMeterized * rowVectorTranslationMatrix(-exampleCenterOfMass)
check("determinant sign unchanged (CGTrader basis, recentered)",
      (determinantOfLinearPart(cgtraderRecentered) < 0) == (determinantOfLinearPart(transformXMinusZYToXYZ) < 0),
      detail: String(format: "det %.2f = s^3 * det(B0) = %.2f", determinantOfLinearPart(cgtraderRecentered),
                     pow(Measured.cgtraderF22MeterizationScale, 3) * determinantOfLinearPart(transformXMinusZYToXYZ)))
check("determinant sign unchanged (Sketchfab F-22 basis, det < 0)",
      (determinantOfLinearPart(f22FinalTransform) < 0) == (determinantOfLinearPart(transformYMinusZXToXYZ) < 0))
check("F-18 length extent through the final transform", lengthAxisExtent([13.654, 5.149, 18.267], f18FinalTransform), 18.267)

// MARK: - Result

print("\n" + (failureCount == 0 ? "All checks passed." : "\(failureCount) check(s) FAILED."))
exit(failureCount == 0 ? 0 : 1)
