//
//  measure_center_of_mass.swift
//  ToyFlightSimulator
//
//  Estimates where each aircraft's center of mass (CoM) sits in the space the engine draws,
//  and reports the recentering offset `c` that the import transform subtracts so that the
//  node origin (the rotation pivot, and the physics body's CoM) lands on it.
//  Companion to plans/claude/aircraft_center_of_mass_recentering_2026-09-25.md; the numbers in
//  that plan came from this script. `verify_center_of_mass_math.swift` checks the matrix math.
//
//  Frames (meters; engine axes +X right, +Y up, +Z nose):
//    native  the vertex coordinates as authored in the file.
//    import  native carried through the registered basis and the meterization scale. It is the
//            frame the engine drew in before recentering, and the frame every hand-authored
//            offset is written in (cameraOffset, AircraftColliderSpec, AircraftLandingGearSpec,
//            child positions such as the F-22 afterburners).
//    body    import minus c. It is the node's local frame after recentering (origin = CoM).
//
//  What it reports for each aircraft:
//    1. The import-frame bounding box and where the current origin sits inside it.
//    2. Whether node transforms change between the animation's start and end. This script
//       measures the START pose, as Model.DrawSpaceNativeExtent does. The engine poses animated
//       assets at the END (UsdModel.initializeAnimationPose), so a moving part can sit elsewhere
//       in the app.
//    3. The nose tip (the vertex with the largest z) and the nozzle center (the bounding-box
//       center of a named part, or of the vertices inside a region box).
//    4. The landing gear read from the geometry: the nose wheel and the two main wheels (lowest
//       points), wheelbase, track, the nose-wheel load share if the CoM stayed at the current
//       origin, and the stations for an 8 / 12 / 15 % share.
//    5. The CoM estimate. Station (z): the current origin, or the station that gives a target
//       nose-wheel share. Height (y): the straight nose->nozzle line at that station. x = 0.
//    6. The authored offsets re-expressed in the body frame (new = old - c), and a roll check:
//       how far the CoM point swings in a 90-degree roll about the current origin.
//
//  How the estimate works, and its limits:
//    - Height: the owner's heuristic, "the roll axis should run from the nose to the nozzles".
//      It is a geometric proxy for the fuselage centerline, not a mass computation (the assets
//      carry no masses).
//    - Station: static balance of a level aircraft on a tricycle gear, taking moments about the
//      main-wheel contact line: noseLoad * wheelbase = weight * (comZ - mainZ). So
//      share = (comZ - mainZ) / wheelbase, and comZ = mainZ + share * wheelbase. Raymer
//      (Aircraft Design: A Conceptual Approach, landing-gear chapter) gives 8-15 % on the nose
//      wheel. This script and the plan use 12 %, the middle of that range.
//    - The gear reading needs the geometry in a gear-down pose. Skinned gear (the F-35) is
//      measured in its bind pose, and the script flags the result as unusable when it does not
//      look like a tricycle gear (nose behind the mains, or wheels far above the lowest vertex).
//    - Aircraft without a named nozzle part use a region box chosen with --aft-profile. The box
//      and the vertices it caught are printed, so check them before trusting the center.
//
//  Usage (paths resolve relative to this file; run from anywhere):
//      swift scripts/measure_center_of_mass.swift [options] [models-dir-override]
//
//  Options:
//      --model <text>   only aircraft whose label contains <text>, case-insensitive (e.g. --model f18)
//      --parts          list every mesh/submesh with its import-frame bounds (to find a nozzle part name)
//      --aft-profile    print 0.2 m slabs of the aft 3 m within |x| < 1.2 m (to choose a nozzle region box)
//      --slices         print the centerline's vertical extent (|x| < 0.3 m) per 1 m station
//
//  Keep in sync: the bases, realWorldLength values, authored offsets and planned c values in
//  `aircraft` below MIRROR ModelLibrary.makeLibrary(), the aircraft classes (cameraOffset,
//  F22's afterburner positions) and the plan. Update them together. The engine ports
//  (decomposeTRS, scaleStrippedTransform, unionTransformedExtent, the row-vector bake) mirror
//  Transform.swift, Model.swift and Mesh.transformMeshBasis, as in measure_models.swift.
//
//  Adding an aircraft: add an AircraftSpec. Run once with --parts (and --aft-profile if no part
//  is named like a nozzle), pick the nozzle source, then read the "CoM estimate" line.
//

import Foundation
import ModelIO
import simd

// MARK: - Basis transforms (mirroring Transform.swift / ModelLibrary.makeLibrary())

// Engine bake convention is row-vector: p_import = p_native * B (Mesh.transformMeshBasis).

// Transform.rotationMatrix(radians: pi, axis: Y_AXIS): F-16 / F-18 OBJs
let rotate180AroundY = float4x4(
    SIMD4<Float>(-1, 0,  0, 0),
    SIMD4<Float>( 0, 1,  0, 0),
    SIMD4<Float>( 0, 0, -1, 0),
    SIMD4<Float>( 0, 0,  0, 1)
)

// Transform.transformXMinusZYToXYZ: CGTrader F-22
let transformXMinusZYToXYZ = float4x4(
    SIMD4<Float>(1,  0, 0, 0),
    SIMD4<Float>(0,  0, 1, 0),
    SIMD4<Float>(0, -1, 0, 0),
    SIMD4<Float>(0,  0, 0, 1)
)

// Transform.transformYMinusZXToXYZ: Sketchfab F-22
let transformYMinusZXToXYZ = float4x4(
    SIMD4<Float>(0, 1,  0, 0),
    SIMD4<Float>(0, 0, -1, 0),
    SIMD4<Float>(1, 0,  0, 0),
    SIMD4<Float>(0, 0,  0, 1)
)

// MARK: - Aircraft table

/// Where the nozzle center comes from.
enum NozzleSource {
    /// A mesh or submesh whose name matches exactly (see --parts).
    case part(String)
    /// Every import-frame vertex inside this box (see --aft-profile). For twin engines the box
    /// spans both nozzles, so its center is the pair's center.
    case region(z: ClosedRange<Float>, maxAbsX: Float, y: ClosedRange<Float>)
}

/// Where the CoM station (z) comes from.
enum StationRule {
    /// Keep the station of the model's current origin (z = 0).
    case currentOrigin
    /// The station where the nose wheel carries this share of the weight (0.12 = 12 %).
    case noseWheelShare(Float)
}

struct AircraftSpec {
    var label: String
    var relPath: String
    var basisName: String
    var basis: float4x4
    /// `realWorldLength:` as registered in ModelLibrary (nil = not meterized, scale 1).
    var realWorldLength: Float?
    var nozzle: NozzleSource
    var station: StationRule
    /// The c the plan adopts, in import-frame meters (mirror ModelLibrary once it is registered).
    /// nil = this aircraft is not recentered.
    var plannedCenterOfMass: SIMD3<Float>?
    /// Hand-authored offsets in the import frame that must become (old - c) after recentering.
    var authoredOffsets: [(name: String, value: SIMD3<Float>)]
    /// True when FlightboxWithPhysics gives this aircraft the legacy 2 m SphereRigidBody
    /// (AircraftColliderSpec.spec(for:) is empty for it). Mirror that switch.
    var usesLegacySphere: Bool = true
}

let aircraft: [AircraftSpec] = [
    AircraftSpec(label: "F16 (f16r.obj)",
                 relPath: "F16/f16r.obj",
                 basisName: "rotate180AroundY", basis: rotate180AroundY,
                 realWorldLength: 15.06,
                 // One OBJ mesh, no nozzle group. The box holds the nozzle ring and stops below
                 // the fin (y 0.6); the ventral fins at |x| ~ 0.55 fall partly inside it.
                 nozzle: .region(z: -6.9 ... -5.6, maxAbsX: 0.6, y: -0.8 ... 0.6),
                 station: .currentOrigin,
                 plannedCenterOfMass: nil,
                 authoredOffsets: [("F16.cameraOffset", [0, 13, -33])]),
    AircraftSpec(label: "F18 (FA-18F.obj)",
                 relPath: "F18/FA-18F.obj",
                 basisName: "rotate180AroundY", basis: rotate180AroundY,
                 realWorldLength: nil,
                 nozzle: .part("EngineNozzles_Paint"),
                 station: .noseWheelShare(0.12),
                 plannedCenterOfMass: [0, 1.928, -1.761],
                 authoredOffsets: [("F18.cameraOffset", [0, 9, -20])]),
    AircraftSpec(label: "F22 CGTrader (usdz)",
                 relPath: "CGTrader/F22_low_poly/cgtrader_F22.usdz",
                 basisName: "transformXMinusZYToXYZ", basis: transformXMinusZYToXYZ,
                 realWorldLength: 18.92,
                 // Single low-poly mesh; the box holds the nozzle pair and stops short of the
                 // stabilators (|x| > 1.2).
                 nozzle: .region(z: -6.9 ... -5.7, maxAbsX: 1.2, y: -0.6 ... 0.6),
                 station: .currentOrigin,
                 plannedCenterOfMass: nil,
                 authoredOffsets: [("F22_CGTrader.cameraOffset", [0, 7, -20])],
                 usesLegacySphere: false),
    AircraftSpec(label: "F22 Sketchfab (usdz)",
                 relPath: "Sketchfab/F-22_Raptor.usdz",
                 basisName: "transformYMinusZXToXYZ", basis: transformYMinusZXToXYZ,
                 realWorldLength: 18.92,
                 // The fuselage tapers into the 2D nozzle pair between z -4.1 and -2.4, with
                 // |y| <= 0.5 there; the box stops below the vertical fins.
                 nozzle: .region(z: -4.1 ... -2.4, maxAbsX: 1.2, y: -0.6 ... 0.6),
                 station: .noseWheelShare(0.12),
                 plannedCenterOfMass: [0, -0.018, 2.512],
                 authoredOffsets: [("F22.cameraOffset", [0, 7, -20]),
                                   ("F22.afterburnerLeft", [-0.600, 0.098, -4]),
                                   ("F22.afterburnerRight", [0.600, 0.098, -4])]),
    AircraftSpec(label: "F35 Sketchfab (usdz)",
                 relPath: "Sketchfab/F-35A_Lightning_II.usdz",
                 basisName: "none (identity)", basis: matrix_identity_float4x4,
                 realWorldLength: 15.67,
                 nozzle: .part("Object_3"),
                 // The skinned gear is in its bind pose here, so the gear rule does not apply.
                 station: .currentOrigin,
                 plannedCenterOfMass: [0, 1.003, 0],
                 authoredOffsets: [("F35.cameraOffset", [0, 6, -18])]),
]

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
    let rotation = float4x4(SIMD4<Float>(matrix.columns.0.xyz / scaleX, 0),
                            SIMD4<Float>(matrix.columns.1.xyz / scaleY, 0),
                            SIMD4<Float>(matrix.columns.2.xyz / scaleZ, 0),
                            SIMD4<Float>(0, 0, 0, 1))
    return (translation, rotation, SIMD3<Float>(scaleX, scaleY, scaleZ))
}

/// Mirrors `Transform.scaleStrippedTransform`: rotation plus scale-normalized translation.
func scaleStrippedTransform(_ matrix: float4x4) -> float4x4 {
    let (worldTranslation, rotation, scale) = decomposeTRS(matrix)
    var result = rotation
    result.columns.3 = SIMD4<Float>(scale.x > 0.0001 ? worldTranslation.x / scale.x : worldTranslation.x,
                                    scale.y > 0.0001 ? worldTranslation.y / scale.y : worldTranslation.y,
                                    scale.z > 0.0001 ? worldTranslation.z / scale.z : worldTranslation.z,
                                    1)
    return result
}

/// The node transform the renderer applies to a mesh: the scale-stripped composed node
/// transform when the asset is animated AND the mesh has a transform component, else identity
/// (Model.DrawSpaceNativeExtent's rule).
func drawnNodeTransform(of mesh: MDLMesh, asset: MDLAsset, atTime time: TimeInterval) -> float4x4 {
    let nodeTransformsApplyAtDraw = asset.endTime > asset.startTime
    guard nodeTransformsApplyAtDraw, mesh.transform != nil else { return matrix_identity_float4x4 }
    return scaleStrippedTransform(MDLTransform.globalTransform(with: mesh, atTime: time))
}

/// Mirrors `Model.DrawSpaceNativeExtent` + `Model.UnionTransformedExtent`: the union of each
/// mesh's LOCAL bounding box carried through its drawn node transform. Meterization calibrates
/// on this extent, so the scale below matches the engine's exactly.
func drawSpaceNativeExtent(asset: MDLAsset, meshes: [MDLMesh]) -> SIMD3<Float> {
    var unionMin = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
    var unionMax = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
    for mesh in meshes {
        let bounds = mesh.boundingBox
        let nodeTransform = drawnNodeTransform(of: mesh, asset: asset, atTime: asset.startTime)
        for cornerIndex in 0..<8 {
            let corner = SIMD3<Float>(cornerIndex & 1 == 0 ? bounds.minBounds.x : bounds.maxBounds.x,
                                      cornerIndex & 2 == 0 ? bounds.minBounds.y : bounds.maxBounds.y,
                                      cornerIndex & 4 == 0 ? bounds.minBounds.z : bounds.maxBounds.z)
            let transformed = simd_mul(nodeTransform, SIMD4<Float>(corner, 1)).xyz
            unionMin = simd_min(unionMin, transformed)
            unionMax = simd_max(unionMax, transformed)
        }
    }
    return meshes.isEmpty ? .zero : unionMax - unionMin
}

/// Mirrors `Model.GetLengthAxisExtent`: extent along engine +Z after the basis (w = 0).
func lengthAxisExtent(nativeExtent: SIMD3<Float>, basis: float4x4) -> Float {
    abs(simd_mul(SIMD4<Float>(nativeExtent, 0), basis).z)
}

/// The import transform without recentering: S * B0, exactly as Model.init composes it today.
func importTransformWithoutRecentering(basis: float4x4, meterizationScale: Float) -> float4x4 {
    float4x4(diagonal: SIMD4<Float>(meterizationScale, meterizationScale, meterizationScale, 1)) * basis
}

/// Row-vector bake of a point (w = 1), as Mesh.transformMeshBasis does.
func bakePoint(_ point: SIMD3<Float>, _ transform: float4x4) -> SIMD3<Float> {
    simd_mul(SIMD4<Float>(point, 1), transform).xyz
}

// MARK: - Geometry helpers

struct Bounds {
    var min = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
    var max = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
    var count = 0
    mutating func add(_ point: SIMD3<Float>) {
        min = simd_min(min, point)
        max = simd_max(max, point)
        count += 1
    }
    var center: SIMD3<Float> { (min + max) / 2 }
    var isEmpty: Bool { count == 0 }
}

/// One named piece of geometry: a whole mesh, or one submesh (the OBJ groups of the F-16 / F-18).
struct Part {
    var meshName: String
    var submeshName: String
    var importPoints: [SIMD3<Float>]
    var label: String { submeshName.isEmpty || submeshName == meshName ? meshName : "\(meshName)/\(submeshName)" }
}

func fmt(_ v: SIMD3<Float>) -> String {
    String(format: "(%7.3f, %7.3f, %7.3f)", v.x, v.y, v.z)
}

func fmt(_ v: Float) -> String {
    String(format: "%.3f", v)
}

/// Mean of the points within `tolerance` of the lowest point of `candidates`, or nil.
func lowestCluster(_ candidates: [SIMD3<Float>], tolerance: Float = 0.06) -> (mean: SIMD3<Float>, count: Int)? {
    guard let lowestY = candidates.map(\.y).min() else { return nil }
    let cluster = candidates.filter { $0.y < lowestY + tolerance }
    return (cluster.reduce(.zero, +) / Float(cluster.count), cluster.count)
}

/// Height of the straight nose->nozzle line at station z (linear interpolation along z).
func noseToNozzleLineHeight(noseTip: SIMD3<Float>, nozzleCenter: SIMD3<Float>, atStationZ stationZ: Float) -> Float {
    let fractionFromNose = (noseTip.z - stationZ) / (noseTip.z - nozzleCenter.z)
    return noseTip.y + fractionFromNose * (nozzleCenter.y - noseTip.y)
}

// MARK: - Arguments

var arguments = Array(CommandLine.arguments.dropFirst())
func takeFlag(_ name: String) -> Bool {
    guard let index = arguments.firstIndex(of: name) else { return false }
    arguments.remove(at: index)
    return true
}
func takeOption(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...(index + 1))
    return value
}
let listParts = takeFlag("--parts")
let showAftProfile = takeFlag("--aft-profile")
let showSlices = takeFlag("--slices")
let modelFilter = takeOption("--model")?.lowercased()

let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let modelsDir: URL = arguments.first.map { URL(fileURLWithPath: $0).standardizedFileURL }
    ?? repoRoot.appendingPathComponent("ToyFlightSimulator Shared/Core/Resources/Models")

guard FileManager.default.fileExists(atPath: modelsDir.path) else {
    fputs("error: models directory not found at \(modelsDir.path)\n", stderr)
    exit(1)
}

print("Models directory: \(modelsDir.path)")
print("All positions are IMPORT-FRAME meters (basis + meterization, before recentering) unless labeled.")

// MARK: - Measure

struct SummaryRow {
    var label: String
    var originAboveLowest: Float
    var lineHeightAtOrigin: Float?
    var estimate: SIMD3<Float>?
    var planned: SIMD3<Float>?
}
var summary: [SummaryRow] = []

for spec in aircraft {
    if let modelFilter, !spec.label.lowercased().contains(modelFilter) { continue }
    let url = modelsDir.appendingPathComponent(spec.relPath)
    print("\n================================================================")
    print(spec.label)
    print("================================================================")
    guard FileManager.default.fileExists(atPath: url.path) else {
        print("  MISSING at \(url.path)")
        continue
    }

    let asset = MDLAsset(url: url)
    let meshes = asset.childObjects(of: MDLMesh.self) as? [MDLMesh] ?? []

    // Meterization exactly as Model.init computes it.
    let nativeLength = lengthAxisExtent(nativeExtent: drawSpaceNativeExtent(asset: asset, meshes: meshes), basis: spec.basis)
    let meterizationScale = spec.realWorldLength.map { $0 / nativeLength } ?? 1
    let importTransform = importTransformWithoutRecentering(basis: spec.basis, meterizationScale: meterizationScale)
    print("  basis \(spec.basisName), meterization scale \(meterizationScale)"
          + (spec.realWorldLength == nil ? " (not meterized)" : " (realWorldLength \(spec.realWorldLength!) m)"))

    // Every vertex in the import frame, grouped into named parts.
    var parts: [Part] = []
    for mesh in meshes {
        let nodeTransform = drawnNodeTransform(of: mesh, asset: asset, atTime: asset.startTime)
        guard let positions = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition, as: .float3) else { continue }
        var importPoints: [SIMD3<Float>] = []
        importPoints.reserveCapacity(mesh.vertexCount)
        for vertexIndex in 0..<mesh.vertexCount {
            let floats = positions.dataStart.advanced(by: vertexIndex * positions.stride).assumingMemoryBound(to: Float.self)
            let nativePoint = SIMD3<Float>(floats[0], floats[1], floats[2])
            importPoints.append(bakePoint(simd_mul(nodeTransform, SIMD4<Float>(nativePoint, 1)).xyz, importTransform))
        }
        let submeshes = (mesh.submeshes as? [MDLSubmesh]) ?? []
        if submeshes.count <= 1 {
            parts.append(Part(meshName: mesh.name, submeshName: submeshes.first?.name ?? "", importPoints: importPoints))
        } else {
            for submesh in submeshes {
                let indexData = submesh.indexBuffer(asIndexType: .uInt32).map()
                let indices = indexData.bytes.bindMemory(to: UInt32.self, capacity: submesh.indexCount)
                let unique = Set((0..<submesh.indexCount).map { Int(indices[$0]) }).filter { $0 < importPoints.count }
                parts.append(Part(meshName: mesh.name, submeshName: submesh.name, importPoints: unique.map { importPoints[$0] }))
            }
        }
    }
    let allPoints = parts.flatMap(\.importPoints)
    var modelBounds = Bounds()
    allPoints.forEach { modelBounds.add($0) }
    guard !modelBounds.isEmpty else {
        print("  no vertex positions found")
        continue
    }

    // 1. Bounds and origin.
    print("  bounds          min \(fmt(modelBounds.min))  max \(fmt(modelBounds.max))")
    print("  bounds center   \(fmt(modelBounds.center))")
    print("  current origin  \(fmt(-modelBounds.min.y)) m above the lowest vertex, "
          + "\(fmt(modelBounds.center.z)) m aft of mid-length (bounds center z)")

    // 2. Node-transform animation.
    if asset.endTime > asset.startTime {
        var movingMeshCount = 0
        var largestChange: Float = 0
        for mesh in meshes where mesh.transform != nil {
            let startMatrix = MDLTransform.globalTransform(with: mesh, atTime: asset.startTime)
            let endMatrix = MDLTransform.globalTransform(with: mesh, atTime: asset.endTime)
            var change: Float = 0
            for column in 0..<4 { change = max(change, simd_length(startMatrix[column] - endMatrix[column])) }
            if change > 1e-4 { movingMeshCount += 1 }
            largestChange = max(largestChange, change)
        }
        print(String(format: "  animation       time %.3f-%.3f s; %d mesh(es) move between start and end "
                     + "(largest matrix change %.3g native units)%@", asset.startTime, asset.endTime,
                     movingMeshCount, largestChange,
                     movingMeshCount > 0 ? "; this script measures the START pose, the engine poses at the END" : ""))
    } else {
        print("  animation       none (empty time range: node transforms never apply at draw)")
    }

    // --parts
    if listParts {
        print("  parts (\(parts.count)):")
        for part in parts {
            var partBounds = Bounds()
            part.importPoints.forEach { partBounds.add($0) }
            guard !partBounds.isEmpty else { continue }
            print("    \(part.label.padding(toLength: 44, withPad: " ", startingAt: 0)) "
                  + "min \(fmt(partBounds.min)) max \(fmt(partBounds.max)) center \(fmt(partBounds.center))")
        }
    }

    // --aft-profile
    if showAftProfile {
        print("  aft profile, |x| < 1.2 m, 0.2 m slabs: z range -> vertex count, x range, y range")
        var slabStart = modelBounds.min.z
        while slabStart < modelBounds.min.z + 3.0 {
            var slab = Bounds()
            allPoints.filter { $0.z >= slabStart && $0.z < slabStart + 0.2 && abs($0.x) < 1.2 }.forEach { slab.add($0) }
            if !slab.isEmpty {
                print(String(format: "    z %6.2f..%6.2f  n %5d  x %6.3f..%6.3f  y %6.3f..%6.3f",
                             slabStart, slabStart + 0.2, slab.count, slab.min.x, slab.max.x, slab.min.y, slab.max.y))
            }
            slabStart += 0.2
        }
    }

    // --slices
    if showSlices {
        print("  centerline slices, |x| < 0.3 m, per 1 m station: y range and midpoint")
        var station = floor(modelBounds.max.z)
        while station >= ceil(modelBounds.min.z) {
            var slice = Bounds()
            allPoints.filter { abs($0.x) < 0.3 && abs($0.z - station) <= 0.5 }.forEach { slice.add($0) }
            if !slice.isEmpty {
                print(String(format: "    z %6.1f: y %7.3f .. %7.3f  mid %7.3f  (n %d)",
                             station, slice.min.y, slice.max.y, slice.center.y, slice.count))
            }
            station -= 1
        }
    }

    // 3. Nose tip and nozzle center.
    let noseTip = allPoints.max(by: { $0.z < $1.z })!
    print("  nose tip        \(fmt(noseTip))   (largest-z vertex)")

    var nozzleBounds = Bounds()
    switch spec.nozzle {
        case .part(let name):
            parts.filter { $0.meshName == name || $0.submeshName == name }
                 .flatMap(\.importPoints)
                 .forEach { nozzleBounds.add($0) }
            print("  nozzle center   \(nozzleBounds.isEmpty ? "NOT FOUND" : fmt(nozzleBounds.center))   "
                  + "(part '\(name)', \(nozzleBounds.count) vertices, min \(fmt(nozzleBounds.min)) max \(fmt(nozzleBounds.max)))")
        case .region(let zRange, let maxAbsX, let yRange):
            allPoints.filter { zRange.contains($0.z) && abs($0.x) <= maxAbsX && yRange.contains($0.y) }
                     .forEach { nozzleBounds.add($0) }
            print("  nozzle center   \(nozzleBounds.isEmpty ? "NOT FOUND" : fmt(nozzleBounds.center))   "
                  + "(region z \(zRange.lowerBound)...\(zRange.upperBound), |x| <= \(maxAbsX), y \(yRange.lowerBound)...\(yRange.upperBound): "
                  + "\(nozzleBounds.count) vertices, min \(fmt(nozzleBounds.min)) max \(fmt(nozzleBounds.max)))")
    }

    // 4. Landing gear from the geometry.
    let noseWheel = lowestCluster(allPoints.filter { abs($0.x) < 0.4 })
    let leftMain = lowestCluster(allPoints.filter { $0.x <= -0.4 })
    let rightMain = lowestCluster(allPoints.filter { $0.x >= 0.4 })
    var mainGearZ: Float?
    var wheelbase: Float?
    if let noseWheel, let leftMain, let rightMain {
        print("  nose wheel      \(fmt(noseWheel.mean))   (lowest point with |x| < 0.4, \(noseWheel.count) vertices)")
        print("  main wheels     \(fmt(leftMain.mean))  \(fmt(rightMain.mean))")
        let candidateMainZ = (leftMain.mean.z + rightMain.mean.z) / 2
        let candidateWheelbase = noseWheel.mean.z - candidateMainZ
        let mirrored = abs(leftMain.mean.x + rightMain.mean.x) < 0.1 && abs(leftMain.mean.z - rightMain.mean.z) < 0.1
        let nearTheGround = max(noseWheel.mean.y, leftMain.mean.y, rightMain.mean.y) < modelBounds.min.y + 0.3
        if candidateWheelbase > 1 && mirrored && nearTheGround {
            mainGearZ = candidateMainZ
            wheelbase = candidateWheelbase
            let shareAtOrigin = (0 - candidateMainZ) / candidateWheelbase
            print("  gear            wheelbase \(fmt(candidateWheelbase)) m, track \(fmt(rightMain.mean.x - leftMain.mean.x)) m, "
                  + String(format: "nose-wheel share if the CoM stays at the origin: %.1f %%", shareAtOrigin * 100))
            if shareAtOrigin < 0 {
                print("                  (negative: the origin is BEHIND the main wheels; a CoM there would tip the jet onto its tail)")
            }
            for share: Float in [0.08, 0.12, 0.15] {
                print(String(format: "                  station for %2.0f %% nose-wheel share: z = %.3f", share * 100,
                             candidateMainZ + share * candidateWheelbase))
            }
        } else {
            print("  gear            NOT USABLE here (not a gear-down tricycle: nose ahead of mains \(candidateWheelbase > 1), "
                  + "mains mirrored \(mirrored), wheels near the lowest vertex \(nearTheGround)). "
                  + "Skinned gear is measured in its bind pose, and some models do not have every wheel down")
        }
    }

    // 5. CoM estimate.
    var lineHeightAtOrigin: Float?
    var estimate: SIMD3<Float>?
    if !nozzleBounds.isEmpty {
        let nozzleCenter = nozzleBounds.center
        lineHeightAtOrigin = noseToNozzleLineHeight(noseTip: noseTip, nozzleCenter: nozzleCenter, atStationZ: 0)
        var stationZ: Float = 0
        var stationSource = "current origin"
        if case .noseWheelShare(let share) = spec.station {
            if let mainGearZ, let wheelbase {
                stationZ = mainGearZ + share * wheelbase
                stationSource = String(format: "%.0f %% nose-wheel share", share * 100)
            } else {
                stationSource = "current origin (gear not usable for the share rule)"
            }
        }
        let height = noseToNozzleLineHeight(noseTip: noseTip, nozzleCenter: nozzleCenter, atStationZ: stationZ)
        estimate = SIMD3<Float>(0, height, stationZ)
        print(String(format: "  line at z = 0   y = %.3f   (the nose->nozzle line tilts %.2f deg nose-down from body +Z)",
                     lineHeightAtOrigin!, atan2(nozzleCenter.y - noseTip.y, noseTip.z - nozzleCenter.z) * 180 / .pi))
        print("  CoM estimate    c = \(fmt(estimate!))   (station: \(stationSource); height: nose->nozzle line; x = 0)")
    }
    if let planned = spec.plannedCenterOfMass {
        let difference = estimate.map { simd_length($0 - planned) }
        print("  plan value      c = \(fmt(planned))" + (difference.map { String(format: "   (differs from the estimate by %.3f m)", $0) } ?? ""))
    } else {
        print("  plan value      none (not recentered)")
    }

    // 6. Re-expressed offsets and the roll check, using the plan value (else the estimate).
    if let centerOfMass = spec.plannedCenterOfMass ?? estimate {
        let source = spec.plannedCenterOfMass == nil ? "estimate" : "plan value"
        print("  re-expressed with the \(source) (new = old - c):")
        for offset in spec.authoredOffsets {
            print("    \(offset.name.padding(toLength: 26, withPad: " ", startingAt: 0)) \(fmt(offset.value)) -> \(fmt(offset.value - centerOfMass))")
        }
        let distanceFromOldRollAxis = simd_length(SIMD2<Float>(centerOfMass.x, centerOfMass.y))
        print(String(format: "  roll check      the CoM point sits %.3f m from today's roll axis: a 90-deg roll swings it %.3f m (0 after recentering)",
                     distanceFromOldRollAxis, distanceFromOldRollAxis * sqrt(2)))
        for (name, point) in [("nose tip", noseTip), ("nozzle center", nozzleBounds.isEmpty ? nil : nozzleBounds.center)] {
            guard let point else { continue }
            let before = simd_length(SIMD2<Float>(point.x, point.y))
            let after = simd_length(SIMD2<Float>(point.x - centerOfMass.x, point.y - centerOfMass.y))
            print(String(format: "                  %@ distance from the roll axis: %.3f m today, %.3f m after", name, before, after))
        }
        // Spec-less aircraft rest on the legacy 2 m SphereRigidBody centered on the node origin.
        if spec.usesLegacySphere {
            print(String(format: "  legacy sphere   lowest vertex above the runway on the 2 m sphere: %.3f m today, %.3f m after",
                         2 + modelBounds.min.y, 2 + modelBounds.min.y - centerOfMass.y))
        }
    }

    summary.append(SummaryRow(label: spec.label, originAboveLowest: -modelBounds.min.y,
                              lineHeightAtOrigin: lineHeightAtOrigin, estimate: estimate, planned: spec.plannedCenterOfMass))
}

// MARK: - Summary

print("\n================================================================")
print("Summary (import-frame meters)")
print("================================================================")
print("Aircraft".padding(toLength: 24, withPad: " ", startingAt: 0)
      + "origin above lowest | line at z=0 | CoM estimate                  | plan value")
for row in summary {
    print(row.label.padding(toLength: 24, withPad: " ", startingAt: 0)
          + String(format: "%19.3f | ", row.originAboveLowest)
          + (row.lineHeightAtOrigin.map { String(format: "%11.3f", $0) } ?? "          -") + " | "
          + (row.estimate.map(fmt) ?? "-".padding(toLength: 27, withPad: " ", startingAt: 0)) + "   | "
          + (row.planned.map(fmt) ?? "none"))
}
