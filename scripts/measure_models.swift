//
//  measure_models.swift
//  ToyFlightSimulator
//
//  Measures every registered model's native (pre-basis-transform) bounding box
//  via ModelIO and derives the meter-scale calibration table from
//  research/claude/meter_scale_units_research_2026-07-20.md §2.2:
//
//    - native extent (MDLAsset.boundingBox, raw file units, stage space)
//    - declared USD units (metersPerUnit / upAxis, read with /usr/bin/usdcat)
//    - the native axis the registered basisTransform maps onto engine +Z
//      ("length axis"), and its extent in native units
//    - in-world length under today's hand-tuned scene scales vs published
//      real aircraft dimensions
//    - the per-model meterization factor s = realLength / nativeLength (§3.2)
//    - span/length proportion cross-check (§2.3.1) and MPU-implied length (§2.3.2)
//
//  The basis matrices and scene scales MIRROR ModelLibrary.makeLibrary() and
//  FlightboxWithPhysics.swift — update both places if those change.
//
//  Caveat: MDLAsset.boundingBox is stage-space (USD root transforms applied),
//  while the engine's basisTransform operates on mesh-local vertex data. A USD
//  root rotation (common on Sketchfab exports) can permute the NON-length axes
//  between the two spaces, so this script only asserts the length-axis mapping
//  — same as the research doc's table.
//
//  Usage (paths resolve relative to this file, run from anywhere):
//      swift scripts/measure_models.swift [models-dir-override]
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

// MARK: - Model table

// Real dimensions (meters): F-22A 18.92 L / 13.56 span (USAF fact sheet);
// F/A-18F 18.31 / 13.62 (NAVAIR, RAAF); F-16C 15.06 / 9.96 with tip missiles;
// F-35A 15.67 / 10.7 (USAF fact sheet). Sources in the research doc.
struct ModelSpec {
    var label: String
    var relPath: String
    var basisName: String? = nil        // nil = registered with no basisTransform (identity)
    var basis: float4x4? = nil
    var sceneScale: Float? = nil        // current hand-tuned scale
    var sceneScaleSource: String? = nil
    var realLength: Float? = nil        // published nose-to-tail length, meters
    var realSpan: Float? = nil          // published wingspan, meters (proportion check only)
}

let specs: [ModelSpec] = [
    ModelSpec(label: "F16 (f16r.obj)", relPath: "F16/f16r.obj",
              basisName: "rotate180AroundY", basis: rotate180AroundY,
              sceneScale: 12.0, sceneScaleSource: "FlightboxWithPhysics.swift:195",
              realLength: 15.06, realSpan: 9.96),
    ModelSpec(label: "F18 (FA-18F.obj)", relPath: "F18/FA-18F.obj",
              basisName: "rotate180AroundY", basis: rotate180AroundY,
              sceneScale: 1.4, sceneScaleSource: "FlightboxWithPhysics.swift:197",
              realLength: 18.31, realSpan: 13.62),
    ModelSpec(label: "F22 CGTrader (usdz)", relPath: "CGTrader/F22_low_poly/cgtrader_F22.usdz",
              basisName: "transformXMinusZYToXYZ", basis: transformXMinusZYToXYZ,
              sceneScale: 3.0, sceneScaleSource: "FlightboxWithPhysics.swift:251",
              realLength: 18.92, realSpan: 13.56),
    ModelSpec(label: "F22 Sketchfab (usdz)", relPath: "Sketchfab/F-22_Raptor.usdz",
              basisName: "transformYMinusZXToXYZ", basis: transformYMinusZXToXYZ,
              sceneScale: 0.25, sceneScaleSource: "FlightboxWithPhysics.swift:245",
              realLength: 18.92, realSpan: 13.56),
    ModelSpec(label: "F35 Sketchfab (usdz)", relPath: "Sketchfab/F-35A_Lightning_II.usdz",
              sceneScale: 0.8, sceneScaleSource: "FlightboxWithPhysics.swift:203",
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
/// engine Z = sum_i v[i] * B[i][2], so pick argmax_i |column2[i]|.
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

// MARK: - Locate the models directory

let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let modelsDir: URL = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
    : repoRoot.appendingPathComponent("ToyFlightSimulator Shared/Core/Resources/Models")

guard FileManager.default.fileExists(atPath: modelsDir.path) else {
    fputs("error: models directory not found at \(modelsDir.path)\n", stderr)
    fputs("       pass it explicitly: swift scripts/measure_models.swift <models-dir>\n", stderr)
    exit(1)
}

print("Models directory: \(modelsDir.path)")

// MARK: - Measure

struct SummaryRow {
    var label: String
    var extent: String
    var declared: String
    var lengthToZ: String
    var scale: String
    var world: String
    var real: String
    var ratio: String
    var factor: String
}

var summaryRows: [SummaryRow] = []
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
    let bb = asset.boundingBox
    let extent = bb.maxBounds - bb.minBounds

    print("  file            \(spec.relPath)")
    print("  native min      \(fmt(bb.minBounds))")
    print("  native max      \(fmt(bb.maxBounds))")
    print("  native extent   \(fmt(extent))    top-level objects: \(asset.count)")

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
                         extent: String(format: "%8.2f x %8.2f x %8.2f", extent.x, extent.y, extent.z),
                         declared: declaredShort,
                         lengthToZ: "-", scale: "-", world: "-", real: "-", ratio: "-", factor: "-")

    if spec.label == "sphere.obj" {
        print(String(format: "  implied radius  %.3f (ColliderOverlayMapping.sphereMeshRadius reference)",
                     extent.x / 2))
    }

    // Derived calibration columns (aircraft only)
    if let realLength = spec.realLength, let sceneScale = spec.sceneScale {
        let basis = spec.basis ?? matrix_identity_float4x4
        let lengthAxis = nativeAxisFeedingEngineZ(basis)
        let nativeLength = extent[lengthAxis]
        let worldToday = nativeLength * sceneScale
        let ratio = worldToday / realLength
        let factor = realLength / nativeLength

        let basisLabel = spec.basisName ?? "none (identity)"
        print("  basis           \(basisLabel)  (engine Z <- native \(axisNames[lengthAxis]))")
        print(String(format: "  length axis     native %@ = %.3f native units",
                     axisNames[lengthAxis], nativeLength))
        print(String(format: "  scene scale     x%g (%@)", sceneScale, spec.sceneScaleSource ?? "-"))
        print(String(format: "  in-world today  %.2f u    vs real %.2f m  ->  %.2fx real size",
                     worldToday, realLength, ratio))
        print(String(format: "  meterization    s = %.2f / %.3f = %.4g", realLength, nativeLength, factor))

        if let mpu = usd?.metersPerUnit {
            let implied = nativeLength * Float(mpu)
            print(String(format: "  MPU implied     %.3f native x %g = %.2f m = %.0f%% of real %.2f m",
                         nativeLength, mpu, implied, implied / realLength * 100, realLength))
        }

        if let realSpan = spec.realSpan {
            // Span = larger of the two non-length native axes (stage space, like the doc).
            let others = [0, 1, 2].filter { $0 != lengthAxis }
            let spanAxis = extent[others[0]] >= extent[others[1]] ? others[0] : others[1]
            let nativeSpan = extent[spanAxis]
            print(String(format: "  proportions     native span/length = %.3f/%.3f = %.3f ; real = %.2f/%.2f = %.3f",
                         nativeSpan, nativeLength, nativeSpan / nativeLength,
                         realSpan, realLength, realSpan / realLength))
        }

        row.lengthToZ = String(format: "%.3f (%@)", nativeLength, axisNames[lengthAxis])
        row.scale = String(format: "x%g", sceneScale)
        row.world = String(format: "%.2f u", worldToday)
        row.real = String(format: "%.2f m", realLength)
        row.ratio = String(format: "%.2fx", ratio)
        row.factor = String(format: "%.4g", factor)
    }

    summaryRows.append(row)
}

// MARK: - Summary table (mirrors research doc §2.2)

print("\n================================================================")
print("Summary (research doc §2.2 table)")
print("================================================================")

let header = SummaryRow(label: "Model", extent: "Native extent (X x Y x Z)", declared: "Declared",
                        lengthToZ: "Length -> engine Z", scale: "Scale", world: "World today",
                        real: "Real", ratio: "vs real", factor: "s=real/native")
for r in [header] + summaryRows {
    print(pad(r.label, 22) + "| " + pad(r.extent, 32) + "| " + pad(r.declared, 22) + "| "
          + lpad(r.lengthToZ, 18) + " | " + lpad(r.scale, 6) + " | " + lpad(r.world, 11) + " | "
          + lpad(r.real, 8) + " | " + lpad(r.ratio, 7) + " | " + lpad(r.factor, 9))
}

if missingCount > 0 {
    fputs("\nerror: \(missingCount) model file(s) missing\n", stderr)
    exit(1)
}
