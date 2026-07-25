//
//  measure_models.swift
//  ToyFlightSimulator
//
//  Reports every registered model's size in the space the engine actually draws,
//  and derives the meter-scale calibration table.
//
//  Per model:
//    - DRAW-SPACE extent: the union of per-mesh MESH-LOCAL bounding boxes, each
//      carried through that mesh's scale-stripped node transform. This mirrors
//      `Model.DrawSpaceNativeExtent` — the space `Mesh.transformMeshBasis` bakes and
//      the renderer draws — so it is the authoritative "native size" and the one
//      meterization calibrates against.
//    - STAGE-SPACE extent (`MDLAsset.boundingBox`): reported as a DIAGNOSTIC only.
//      It composes the full USD node hierarchy INCLUDING scale, which the engine
//      strips at draw time (`TransformComponent` keeps rotation + scale-normalized
//      translation so `GameObject.setScale()` stays the sole gameplay scale). The
//      stage/draw ratio on the length axis IS that stripped node scale — it is 5.78x
//      on the Sketchfab F-22 and 15.03x on the Sketchfab F-35, and calibrating
//      against stage space is what made those two render that many times too small.
//      See debugging/claude/sketchfab_f22_f35_meterization_node_scale.md.
//    - declared USD units (metersPerUnit / upAxis, read with /usr/bin/usdcat), and
//      the stage length they imply — MPU describes stage units, so that check stays
//      in stage space.
//    - the native axis the registered basisTransform maps onto engine +Z ("length
//      axis"), its draw-space extent, and the meterization factor Model.init derives:
//      s = realWorldLength / drawSpaceLength.
//    - ENGINE SIZE: draw extent through the basis, x s, x scene scale — the model's
//      size in meters as the game world sees it (span X, height Y, length Z).
//    - span/length proportion cross-check in both spaces. A draw-space proportion that
//      disagrees with stage space means per-mesh node translations land differently
//      than the USD stage intends (TransformComponent divides the COMPOSED translation
//      by the COMPOSED scale, which is not the same as unscaling each hierarchy level).
//      That is pre-existing engine behavior this script mirrors, not a measurement bug.
//
//  The basis matrices, registered realWorldLength values, and scene scales MIRROR
//  ModelLibrary.makeLibrary() and FlightboxWithPhysics.swift — update both places if
//  those change. The engine-code ports below (decomposeTRS / scaleStrippedTransform /
//  union extent / length-axis extent) mirror Transform.swift and Model.swift; keep
//  them in sync so the script cannot drift from what ships.
//
//  Caveat: stage space and draw space can PERMUTE the non-length axes relative to one
//  another (a USD root rotation, common on Sketchfab exports — the F-22's root swaps
//  Y and Z). Only the length-axis mapping is asserted across both spaces; read the
//  draw-space extent for anything else.
//
//  Usage (paths resolve relative to this file, run from anywhere):
//      swift scripts/measure_models.swift [--verbose] [models-dir-override]
//

import Foundation
import ModelIO
import simd

// MARK: - Basis transforms (mirroring Transform.swift / ModelLibrary.makeLibrary())

// Engine convention is row-vector: v_engine = v * B (Mesh.transformMeshBasis),
// so engine axis j receives sum_i v[i] * B[i][j] — read column j component-wise.

// Transform.rotationMatrix(radians: pi, axis: Y_AXIS) — F-16 / F-18 OBJs (det = +1)
let rotate180AroundY = float4x4(
    SIMD4<Float>(-1, 0,  0, 0),
    SIMD4<Float>( 0, 1,  0, 0),
    SIMD4<Float>( 0, 0, -1, 0),
    SIMD4<Float>( 0, 0,  0, 1)
)

// Transform.transformXMinusZYToXYZ — CGTrader F-22 (det = -1)
let transformXMinusZYToXYZ = float4x4(
    SIMD4<Float>(1,  0, 0, 0),
    SIMD4<Float>(0,  0, 1, 0),
    SIMD4<Float>(0, -1, 0, 0),
    SIMD4<Float>(0,  0, 0, 1)
)

// Transform.transformYMinusZXToXYZ — Sketchfab F-22 (det = -1)
let transformYMinusZXToXYZ = float4x4(
    SIMD4<Float>(0, 1,  0, 0),
    SIMD4<Float>(0, 0, -1, 0),
    SIMD4<Float>(1, 0,  0, 0),
    SIMD4<Float>(0, 0,  0, 1)
)

// MARK: - Engine ports (Transform.swift / Model.swift)

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3<Float>(x, y, z) }
}

/// Mirrors `Transform.decomposeTRS`.
func decomposeTRS(_ matrix: float4x4) -> (translation: SIMD3<Float>, rotation: float4x4, scale: SIMD3<Float>) {
    let translation = matrix.columns.3.xyz
    let scaleX = length(matrix.columns.0.xyz)
    let scaleY = length(matrix.columns.1.xyz)
    let scaleZ = length(matrix.columns.2.xyz)
    let col0 = SIMD4<Float>(matrix.columns.0.xyz / scaleX, 0)
    let col1 = SIMD4<Float>(matrix.columns.1.xyz / scaleY, 0)
    let col2 = SIMD4<Float>(matrix.columns.2.xyz / scaleZ, 0)
    let rotation = float4x4(col0, col1, col2, SIMD4<Float>(0, 0, 0, 1))
    return (translation, rotation, SIMD3<Float>(scaleX, scaleY, scaleZ))
}

/// Mirrors `Transform.matrixFromTR`.
func matrixFromTR(translation: SIMD3<Float>, rotation: float4x4) -> float4x4 {
    var result = rotation
    result.columns.3 = SIMD4<Float>(translation, 1)
    return result
}

/// Mirrors `Transform.scaleStrippedTransform` — the node-transform shape the renderer
/// applies: rotation plus scale-normalized translation, scale itself dropped.
func scaleStrippedTransform(_ matrix: float4x4) -> float4x4 {
    let (worldTranslation, rotation, scale) = decomposeTRS(matrix)
    let normalizedTranslation = SIMD3<Float>(
        scale.x > 0.0001 ? worldTranslation.x / scale.x : worldTranslation.x,
        scale.y > 0.0001 ? worldTranslation.y / scale.y : worldTranslation.y,
        scale.z > 0.0001 ? worldTranslation.z / scale.z : worldTranslation.z
    )
    return matrixFromTR(translation: normalizedTranslation, rotation: rotation)
}

/// Mirrors `Model.GetLengthAxisExtent`: extent along engine +Z after the basis.
/// Row-vector `v * B`, w = 0 because an extent is a size, not a point.
func getLengthAxisExtent(nativeExtent: SIMD3<Float>, basisTransform: float4x4? = nil) -> Float {
    let transformed = (SIMD4<Float>(nativeExtent, 0) * (basisTransform ?? matrix_identity_float4x4)).xyz
    return abs(transformed.z)
}

/// The whole extent through the basis (same row-vector convention as
/// `getLengthAxisExtent`, which reads only the Z component of this).
func basisTransformedExtent(_ nativeExtent: SIMD3<Float>, _ basisTransform: float4x4?) -> SIMD3<Float> {
    abs((SIMD4<Float>(nativeExtent, 0) * (basisTransform ?? matrix_identity_float4x4)).xyz)
}

/// One mesh as the draw-space measurement sees it.
struct MeshMeasurement {
    var name: String
    var localMin: SIMD3<Float>
    var localMax: SIMD3<Float>
    /// Scale-stripped composed node transform, or identity when the engine would not
    /// apply it (no transform component, or an empty asset time range).
    var nodeTransform: float4x4
    /// Composed node scale — diagnostic only; this is what the draw path strips.
    var composedScale: SIMD3<Float>
    var nodeTransformApplies: Bool

    var localExtent: SIMD3<Float> { localMax - localMin }
}

/// Mirrors `Model.DrawSpaceNativeExtent`'s per-mesh gathering, keeping the composed
/// scale around for reporting. A mesh's node transform participates exactly when the
/// renderer applies it: the mesh has a transform component AND the asset is animated
/// (`TransformComponent.setCurrentTransform` leaves identity on an empty time range —
/// the Sketchfab F-22 is such an asset).
func measureMeshes(asset: MDLAsset, mdlMeshes: [MDLMesh]) -> [MeshMeasurement] {
    let nodeTransformsApplyAtDraw = asset.endTime > asset.startTime
    return mdlMeshes.map { mesh in
        let bounds = mesh.boundingBox
        let hasTransform = mesh.transform != nil
        let composed = hasTransform
            ? MDLTransform.globalTransform(with: mesh, atTime: asset.startTime)
            : matrix_identity_float4x4
        let applies = nodeTransformsApplyAtDraw && hasTransform
        return MeshMeasurement(name: mesh.name.isEmpty ? "<unnamed>" : mesh.name,
                               localMin: bounds.minBounds,
                               localMax: bounds.maxBounds,
                               nodeTransform: applies ? scaleStrippedTransform(composed) : matrix_identity_float4x4,
                               composedScale: decomposeTRS(composed).scale,
                               nodeTransformApplies: applies)
    }
}

/// Mirrors `Model.UnionTransformedExtent`: union AABB extent of local bounds each
/// carried through its own node transform (column-vector ModelIO convention, p' = M·p).
func unionTransformedExtent(_ measurements: [MeshMeasurement]) -> SIMD3<Float> {
    guard !measurements.isEmpty else { return .zero }
    var unionMin = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
    var unionMax = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
    for measurement in measurements {
        for cornerIndex in 0..<8 {
            let corner = SIMD3<Float>(cornerIndex & 1 == 0 ? measurement.localMin.x : measurement.localMax.x,
                                      cornerIndex & 2 == 0 ? measurement.localMin.y : measurement.localMax.y,
                                      cornerIndex & 4 == 0 ? measurement.localMin.z : measurement.localMax.z)
            let transformed = simd_mul(measurement.nodeTransform, SIMD4<Float>(corner, 1)).xyz
            unionMin = simd_min(unionMin, transformed)
            unionMax = simd_max(unionMax, transformed)
        }
    }
    return unionMax - unionMin
}

// MARK: - Model table

// Real dimensions (meters): F-22A 18.92 L / 13.56 span (USAF fact sheet);
// F/A-18F 18.31 / 13.62 (NAVAIR, RAAF); F-16C 15.06 / 9.96 with tip missiles;
// F-35A 15.67 / 10.7 (USAF fact sheet). Sources in the research doc.
struct ModelSpec {
    var label: String
    var relPath: String
    var basisName: String? = nil            // nil = registered with no basisTransform (identity)
    var basis: float4x4? = nil
    /// `realWorldLength:` as registered in ModelLibrary.makeLibrary(). nil = not
    /// meterized (Model.init leaves the basis alone and native units ship as-is).
    var registeredRealWorldLength: Float? = nil
    /// Scale the scene applies. Meterized models render at 1.0
    /// ("Models are meterized at import (1 unit = 1 m), so aircraft use scale 1.0" —
    /// FlightboxWithPhysics.applyAircraftSwap); kept as a field so a re-introduced
    /// hand-tuned scale shows up in the drawn-size column instead of hiding.
    var sceneScale: Float = 1.0
    var realLength: Float? = nil            // published nose-to-tail length, meters
    var realSpan: Float? = nil              // published wingspan, meters (proportion check only)
}

let specs: [ModelSpec] = [
    ModelSpec(label: "F16 (f16r.obj)", relPath: "F16/f16r.obj",
              basisName: "rotate180AroundY", basis: rotate180AroundY,
              registeredRealWorldLength: 15.06,
              realLength: 15.06, realSpan: 9.96),
    // Deliberately NOT meterized: native units are already meters, and skipping keeps
    // the fuselage congruent with the SingleSubmeshMeshLibrary extraction path (which
    // bypasses Model.init). See ModelLibrary.makeLibrary().
    ModelSpec(label: "F18 (FA-18F.obj)", relPath: "F18/FA-18F.obj",
              basisName: "rotate180AroundY", basis: rotate180AroundY,
              realLength: 18.31, realSpan: 13.62),
    ModelSpec(label: "F22 CGTrader (usdz)", relPath: "CGTrader/F22_low_poly/cgtrader_F22.usdz",
              basisName: "transformXMinusZYToXYZ", basis: transformXMinusZYToXYZ,
              registeredRealWorldLength: 18.92,
              realLength: 18.92, realSpan: 13.56),
    ModelSpec(label: "F22 Sketchfab (usdz)", relPath: "Sketchfab/F-22_Raptor.usdz",
              basisName: "transformYMinusZXToXYZ", basis: transformYMinusZXToXYZ,
              registeredRealWorldLength: 18.92,
              realLength: 18.92, realSpan: 13.56),
    ModelSpec(label: "F35 Sketchfab (usdz)", relPath: "Sketchfab/F-35A_Lightning_II.usdz",
              registeredRealWorldLength: 15.67,
              realLength: 15.67, realSpan: 10.7),
    ModelSpec(label: "sphere.obj", relPath: "Sphere/sphere.obj"),
    ModelSpec(label: "quad.obj", relPath: "Quad/quad.obj"),
    ModelSpec(label: "Temple.obj", relPath: "Temple/Temple.obj"),
]

// MARK: - Declared USD units (usdcat)

struct USDStageInfo {
    var metersPerUnit: Double?
    var upAxis: String?
}

func readUSDStageInfo(path: String) -> USDStageInfo? {
    let lowered = path.lowercased()
    guard lowered.hasSuffix(".usdz") || lowered.hasSuffix(".usdc") || lowered.hasSuffix(".usda") else {
        return nil
    }
    let usdcat = "/usr/bin/usdcat"
    guard FileManager.default.isExecutableFile(atPath: usdcat) else {
        fputs("warning: \(usdcat) not found; skipping declared-units read\n", stderr)
        return USDStageInfo()
    }
    // Stage metadata lives in the opening parenthetical block; head keeps usdcat
    // from streaming the entire (potentially huge) flattened layer.
    let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", "\(usdcat) '\(escaped)' 2>/dev/null | head -120"]
    let pipe = Pipe()
    process.standardOutput = pipe
    do { try process.run() } catch { return USDStageInfo() }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    var info = USDStageInfo()
    guard let text = String(data: data, encoding: .utf8) else { return info }
    for rawLine in text.split(separator: "\n") {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("metersPerUnit"), let value = line.split(separator: "=").last {
            info.metersPerUnit = Double(value.trimmingCharacters(in: .whitespaces))
        } else if line.hasPrefix("upAxis"), let value = line.split(separator: "=").last {
            info.upAxis = value.trimmingCharacters(in: CharacterSet(charactersIn: " \""))
        }
    }
    return info
}

func mpuUnitName(_ mpu: Double) -> String {
    switch mpu {
    case 1:      return "m"
    case 0.01:   return "cm"
    case 0.001:  return "mm"
    case 0.0254: return "in"
    default:     return String(format: "%g m", mpu)
    }
}

// MARK: - Basis helpers

/// Index of the native axis that the (row-vector) basis maps onto engine +Z.
/// engine Z = sum_i v[i] * B[i][2], so pick argmax_i |column2[i]|. Labeling only —
/// the reported length always comes from `getLengthAxisExtent`.
func nativeAxisFeedingEngineZ(_ basis: float4x4) -> Int {
    let column2 = basis[2]
    let magnitudes = [abs(column2.x), abs(column2.y), abs(column2.z)]
    return magnitudes.firstIndex(of: magnitudes.max()!)!
}

let axisNames = ["X", "Y", "Z"]

// MARK: - Formatting

func fmt(_ v: SIMD3<Float>) -> String {
    String(format: "[%9.3f, %9.3f, %9.3f]", v.x, v.y, v.z)
}

func pad(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}

func lpad(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
}

// MARK: - Arguments / locate the models directory

let arguments = CommandLine.arguments.dropFirst()
let verbose = arguments.contains("--verbose") || arguments.contains("-v")
let positional = arguments.filter { !$0.hasPrefix("-") }

let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let modelsDir: URL = positional.first.map { URL(fileURLWithPath: $0).standardizedFileURL }
    ?? repoRoot.appendingPathComponent("ToyFlightSimulator Shared/Core/Resources/Models")

guard FileManager.default.fileExists(atPath: modelsDir.path) else {
    fputs("error: models directory not found at \(modelsDir.path)\n", stderr)
    fputs("       pass it explicitly: swift scripts/measure_models.swift <models-dir>\n", stderr)
    exit(1)
}

print("Models directory: \(modelsDir.path)")
print("Sizes are DRAW-SPACE (what the engine bakes and renders); stage-space "
      + "MDLAsset.boundingBox is shown for contrast only.")

// MARK: - Measure

struct SummaryRow {
    var label: String
    var drawExtent: String
    var declared: String
    var lengthToZ: String
    var stageOverDraw: String
    var factor: String
    var real: String
    var drawn: String
    var ratio: String
}

var summaryRows: [SummaryRow] = []
var notes: [String] = []
var missingCount = 0

for spec in specs {
    let url = modelsDir.appendingPathComponent(spec.relPath)
    print("\n----------------------------------------------------------------")
    print(spec.label)
    print("----------------------------------------------------------------")

    guard FileManager.default.fileExists(atPath: url.path) else {
        print("  MISSING at \(url.path)")
        missingCount += 1
        continue
    }

    let asset = MDLAsset(url: url)
    let stageBB = asset.boundingBox
    let stageExtent = stageBB.maxBounds - stageBB.minBounds

    let mdlMeshes = asset.childObjects(of: MDLMesh.self) as? [MDLMesh] ?? []
    let measurements = measureMeshes(asset: asset, mdlMeshes: mdlMeshes)
    let drawExtent = unionTransformedExtent(measurements)

    let drawExtentMarker = spec.registeredRealWorldLength == nil
        ? "<- the size the engine draws"
        : "<- the size the engine draws; meterization calibrates on THIS"
    print("  file            \(spec.relPath)")
    print("  draw extent     \(fmt(drawExtent))    \(drawExtentMarker)")
    print("  stage extent    \(fmt(stageExtent))    (MDLAsset.boundingBox, diagnostic)")
    print("  stage min/max   \(fmt(stageBB.minBounds))  \(fmt(stageBB.maxBounds))")

    // Node-transform status: the reason draw and stage can disagree.
    let animated = asset.endTime > asset.startTime
    let appliedCount = measurements.filter(\.nodeTransformApplies).count
    let nodeStatus = animated
        ? "APPLY at draw (\(appliedCount)/\(measurements.count) meshes)"
        : "NEVER apply at draw (empty asset time range)"
    print(String(format: "  node transforms %@   asset time range %.3f-%.3f, top-level objects: %d",
                 nodeStatus, asset.startTime, asset.endTime, asset.count))

    let composedScales = measurements.map { max($0.composedScale.x, max($0.composedScale.y, $0.composedScale.z)) }
    if let minScale = composedScales.min(), let maxScale = composedScales.max(),
       maxScale > 1.0001 || minScale < 0.9999 {
        print(String(format: "  node scale      composed %.4f-%.4f across meshes — STRIPPED at draw "
                     + "(GameObject.setScale() is the sole gameplay scale)", minScale, maxScale))
    }

    if verbose && !measurements.isEmpty {
        print("  per-mesh (\(measurements.count)):")
        for measurement in measurements {
            print("    " + pad(measurement.name, 28)
                  + "local " + fmt(measurement.localExtent)
                  + String(format: "  node scale [%.4f, %.4f, %.4f]%@",
                           measurement.composedScale.x, measurement.composedScale.y,
                           measurement.composedScale.z,
                           measurement.nodeTransformApplies ? "" : "  (node transform not applied)"))
        }
    }

    // Declared units
    let usd = readUSDStageInfo(path: url.path)
    var declaredShort = "none (OBJ)"
    if let usd {
        if let mpu = usd.metersPerUnit {
            let up = usd.upAxis ?? "?"
            print("  declared units  metersPerUnit = \(String(format: "%g", mpu)) "
                  + "(1 unit = 1 \(mpuUnitName(mpu))), upAxis = \(up)")
            declaredShort = "MPU=\(String(format: "%g", mpu)) (\(mpuUnitName(mpu))), \(up)-up"
        } else {
            print("  declared units  metersPerUnit unauthored (USD fallback 0.01 = cm), "
                  + "upAxis = \(usd.upAxis ?? "unauthored (fallback Y)")")
            declaredShort = "unauthored"
        }
    } else {
        print("  declared units  none (OBJ carries no unit metadata)")
    }

    var row = SummaryRow(label: spec.label,
                         drawExtent: String(format: "%8.2f x %8.2f x %8.2f",
                                            drawExtent.x, drawExtent.y, drawExtent.z),
                         declared: declaredShort,
                         lengthToZ: "-", stageOverDraw: "-", factor: "-",
                         real: "-", drawn: "-", ratio: "-")

    if spec.label == "sphere.obj" {
        print(String(format: "  implied radius  %.3f (sphere-collider overlay reference — "
                     + "ColliderOverlayMapping.sphereMeshRadius in the compound-bodies plan)",
                     drawExtent.x / 2))
    }

    // Derived calibration columns (aircraft only)
    if let realLength = spec.realLength {
        let basis = spec.basis ?? matrix_identity_float4x4
        let lengthAxis = nativeAxisFeedingEngineZ(basis)
        let drawLength = getLengthAxisExtent(nativeExtent: drawExtent, basisTransform: basis)
        let stageLength = getLengthAxisExtent(nativeExtent: stageExtent, basisTransform: basis)

        // Meterization: Model.init folds realWorldLength / drawLength into the basis.
        // Unmeterized registrations ship native units unchanged (s = 1).
        let meterizationScale = spec.registeredRealWorldLength.map { $0 / drawLength } ?? 1.0
        let engineSize = basisTransformedExtent(drawExtent, basis) * meterizationScale * spec.sceneScale
        let drawnLength = drawLength * meterizationScale * spec.sceneScale
        let ratio = drawnLength / realLength

        let basisLabel = spec.basisName ?? "none (identity)"
        print("  basis           \(basisLabel)  (engine Z <- native \(axisNames[lengthAxis]))")
        print(String(format: "  length axis     draw %.3f native units on %@   (stage %.3f)",
                     drawLength, axisNames[lengthAxis], stageLength))

        if stageLength > 0, abs(stageLength / drawLength - 1) > 0.001 {
            let k = stageLength / drawLength
            print(String(format: "  stage/draw      %.4fx — node scale the renderer strips; "
                         + "calibrating on stage space would render this %.4fx too small", k, k))
            notes.append(String(format: "%@: stage space over-reports the length axis by %.4fx "
                                + "(stripped node scale) — always calibrate on the draw-space value.",
                                spec.label, k))
        }

        if let registered = spec.registeredRealWorldLength {
            print(String(format: "  meterization    registered realWorldLength = %.2f m  ->  "
                         + "s = %.2f / %.3f = %.6g", registered, registered, drawLength, meterizationScale))
        } else {
            print("  meterization    NOT registered (no realWorldLength) — native units ship as-is")
            notes.append("\(spec.label): not meterized (no realWorldLength registered); "
                         + "its native units are taken as meters.")
        }

        print(String(format: "  engine size     %@ m   (span X, height Y, length Z; draw extent x s x scene scale %g)",
                     fmt(engineSize), spec.sceneScale))
        print(String(format: "  vs real         length %.2f m drawn vs %.2f m published  ->  %.3fx",
                     drawnLength, realLength, ratio))

        if abs(ratio - 1) > 0.02 {
            notes.append(String(format: "%@: drawn length %.2f m is %.1f%% off the published %.2f m.",
                                spec.label, drawnLength, (ratio - 1) * 100, realLength))
        }

        // MPU describes STAGE units, so the declared-length check stays in stage space.
        if let mpu = usd?.metersPerUnit {
            let implied = stageLength * Float(mpu)
            print(String(format: "  MPU implied     stage %.3f x %g = %.2f m = %.0f%% of real %.2f m "
                         + "(file metadata is untrustworthy — hence meterization)",
                         stageLength, mpu, implied, implied / realLength * 100, realLength))
        }

        if let realSpan = spec.realSpan {
            // Span = larger of the two non-length axes, measured in each space.
            let others = [0, 1, 2].filter { $0 != lengthAxis }
            func span(_ extent: SIMD3<Float>) -> Float {
                max(extent[others[0]], extent[others[1]])
            }
            let drawSpanRatio = span(drawExtent) / drawLength
            let stageSpanRatio = stageLength > 0 ? span(stageExtent) / stageLength : 0
            print(String(format: "  proportions     span/length: draw %.3f ; stage %.3f ; real %.2f/%.2f = %.3f",
                         drawSpanRatio, stageSpanRatio, realSpan, realLength, realSpan / realLength))

            if stageSpanRatio > 0, abs(drawSpanRatio / stageSpanRatio - 1) > 0.05 {
                print("  note            draw-space proportions differ from stage: per-mesh node "
                      + "translations are unscaled by the COMPOSED scale, so parts sit slightly")
                print("                  differently than the USD stage intends. Pre-existing draw "
                      + "behavior this measurement mirrors (see the debugging doc, §7).")
            }
        }

        row.lengthToZ = String(format: "%.3f (%@)", drawLength, axisNames[lengthAxis])
        row.stageOverDraw = stageLength > 0 ? String(format: "%.2fx", stageLength / drawLength) : "-"
        row.factor = spec.registeredRealWorldLength == nil
            ? "none"
            : String(format: "%.4g", meterizationScale)
        row.real = String(format: "%.2f m", realLength)
        row.drawn = String(format: "%.2f m", drawnLength)
        row.ratio = String(format: "%.2fx", ratio)
    }

    summaryRows.append(row)
}

// MARK: - Summary table

print("\n================================================================")
print("Summary — draw-space sizes (the space the engine renders)")
print("================================================================")

let header = SummaryRow(label: "Model", drawExtent: "Draw extent (X x Y x Z)", declared: "Declared",
                        lengthToZ: "Length -> engine Z", stageOverDraw: "stage/draw",
                        factor: "s=real/native", real: "Real", drawn: "Drawn", ratio: "vs real")
for r in [header] + summaryRows {
    print(pad(r.label, 22) + "| " + pad(r.drawExtent, 32) + "| " + pad(r.declared, 22) + "| "
          + lpad(r.lengthToZ, 18) + " | " + lpad(r.stageOverDraw, 10) + " | " + lpad(r.factor, 13) + " | "
          + lpad(r.real, 8) + " | " + lpad(r.drawn, 8) + " | " + lpad(r.ratio, 7))
}

if !notes.isEmpty {
    print("\nNotes:")
    for note in notes {
        print("  - \(note)")
    }
}

if missingCount > 0 {
    fputs("\nerror: \(missingCount) model file(s) missing\n", stderr)
    exit(1)
}
