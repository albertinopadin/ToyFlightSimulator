//
//  inspect_winding.swift
//  ToyFlightSimulator
//
//  Diagnostic: for each MDLMesh / MDLSubmesh in an asset, decide whether the
//  triangle index order agrees with the stored vertex normals (i.e. is the
//  asset authored "outward-facing CCW" relative to its own normals?), then
//  report per-submesh majority. Also runs the same test under an optional
//  basis transform that mirrors what `Mesh.transformMeshBasis` does in the
//  engine, so we can see what happens after the engine's load-time mutation.
//
//  Usage:
//      swift inspect_winding.swift <usdz-or-obj-path> [--basis <name>] ...
//
//  Where <name> is one of:
//      none                          (default, no transform)
//      f22-sketchfab                 (Transform.transformYMinusZXToXYZ, det = -1)
//      f22-cgtrader                  (Transform.transformXMinusZYToXYZ, det = -1)
//      f18                           (180° rotation about Y, det = +1)
//
//  Each --basis flag applies to the FOLLOWING path argument. You can mix
//  files freely:
//      swift inspect_winding.swift \
//          path/F-35A_Lightning_II.usdz \
//          --basis f22-sketchfab path/F-22_Raptor.usdz \
//          --basis f18 path/FA-18F.obj
//

import Foundation
import ModelIO
import MetalKit
import simd

// MARK: - Basis transforms (mirroring Transform.swift)

let basisNone = matrix_identity_float4x4

// Transform.transformYMinusZXToXYZ — Sketchfab F-22 (det = -1)
let basisYMinusZXtoXYZ = float4x4(
    SIMD4<Float>(0, 1,  0, 0),
    SIMD4<Float>(0, 0, -1, 0),
    SIMD4<Float>(1, 0,  0, 0),
    SIMD4<Float>(0, 0,  0, 1)
)

// Transform.transformXMinusZYToXYZ — CGTrader F-22 (det = -1)
let basisXMinusZYtoXYZ = float4x4(
    SIMD4<Float>(1,  0, 0, 0),
    SIMD4<Float>(0,  0, 1, 0),
    SIMD4<Float>(0, -1, 0, 0),
    SIMD4<Float>(0,  0, 0, 1)
)

// 180° rotation about Y — F-18 (det = +1)
let basisF18Rotation: float4x4 = {
    let c: Float = -1, s: Float = 0  // cos(180°), sin(180°)
    return float4x4(
        SIMD4<Float>( c, 0, s, 0),
        SIMD4<Float>( 0, 1, 0, 0),
        SIMD4<Float>(-s, 0, c, 0),
        SIMD4<Float>( 0, 0, 0, 1)
    )
}()

func basisNamed(_ name: String) -> (label: String, matrix: float4x4)? {
    switch name {
    case "none":          return ("identity",                  basisNone)
    case "f22-sketchfab": return ("transformYMinusZXToXYZ",    basisYMinusZXtoXYZ)
    case "f22-cgtrader":  return ("transformXMinusZYToXYZ",    basisXMinusZYtoXYZ)
    case "f18":           return ("180deg rotation about Y",   basisF18Rotation)
    default:              return nil
    }
}

// MARK: - Vertex descriptor matching the engine

func engineVertexDescriptor() -> MDLVertexDescriptor {
    let d = MDLVertexDescriptor()
    var offset = 0
    func add(_ name: String, _ format: MDLVertexFormat, size: Int) {
        d.attributes[d.attributes.count > offset / 8 ? offset / 8 : 0] = MDLVertexAttribute()
        // (We rely on Model I/O's attribute auto-population by name below.)
        _ = name; _ = format; _ = size
    }
    // Simpler: ask Model I/O to populate by name and let it lay things out.
    let attrs: [(String, MDLVertexFormat)] = [
        (MDLVertexAttributePosition,            .float3),
        (MDLVertexAttributeColor,               .float4),
        (MDLVertexAttributeTextureCoordinate,   .float2),
        (MDLVertexAttributeNormal,              .float3),
        (MDLVertexAttributeTangent,             .float3),
        (MDLVertexAttributeBitangent,           .float3),
        (MDLVertexAttributeJointIndices,        .uShort4),
        (MDLVertexAttributeJointWeights,        .float4),
    ]
    var off = 0
    for (i, (name, format)) in attrs.enumerated() {
        let attr = MDLVertexAttribute(name: name, format: format, offset: off, bufferIndex: 0)
        d.attributes[i] = attr
        off += sizeOf(format)
    }
    d.layouts[0] = MDLVertexBufferLayout(stride: off)
    return d
}

func sizeOf(_ format: MDLVertexFormat) -> Int {
    switch format {
    case .float2:  return 8
    case .float3:  return 12
    case .float4:  return 16
    case .uShort4: return 8
    default:       return 16
    }
}

// MARK: - Index decoding

func decodeIndices(_ submesh: MDLSubmesh) -> [Int] {
    let count = submesh.indexCount
    let buffer = submesh.indexBuffer.map()
    let bytes = buffer.bytes

    switch submesh.indexType {
    case .uInt8:
        let p = bytes.bindMemory(to: UInt8.self, capacity: count)
        return (0..<count).map { Int(p[$0]) }
    case .uInt16:
        let p = bytes.bindMemory(to: UInt16.self, capacity: count)
        return (0..<count).map { Int(p[$0]) }
    case .uInt32:
        let p = bytes.bindMemory(to: UInt32.self, capacity: count)
        return (0..<count).map { Int(p[$0]) }
    @unknown default:
        return []
    }
}

func triangleTriples(_ submesh: MDLSubmesh) -> [(Int, Int, Int)] {
    let indices = decodeIndices(submesh)
    switch submesh.geometryType {
    case .triangles:
        var result: [(Int, Int, Int)] = []
        result.reserveCapacity(indices.count / 3)
        var i = 0
        while i + 2 < indices.count {
            result.append((indices[i], indices[i + 1], indices[i + 2]))
            i += 3
        }
        return result

    case .triangleStrips:
        guard indices.count >= 3 else { return [] }
        var result: [(Int, Int, Int)] = []
        result.reserveCapacity(indices.count - 2)
        for i in 0..<(indices.count - 2) {
            if i.isMultiple(of: 2) {
                result.append((indices[i], indices[i + 1], indices[i + 2]))
            } else {
                // Normalize odd-strip orientation so every triple represents the
                // same "front" interpretation as the even strip triples.
                result.append((indices[i + 1], indices[i], indices[i + 2]))
            }
        }
        return result

    default:
        return []
    }
}

// MARK: - Vertex attribute reads

func readFloat3(_ data: MDLVertexAttributeData, vertex: Int) -> SIMD3<Float>? {
    let p = data.dataStart.advanced(by: vertex * data.stride)
    switch data.format {
    case .float3:
        return p.assumingMemoryBound(to: SIMD3<Float>.self).pointee
    case .float4:
        let v = p.assumingMemoryBound(to: SIMD4<Float>.self).pointee
        return SIMD3<Float>(v.x, v.y, v.z)
    case .float2:
        let v = p.assumingMemoryBound(to: SIMD2<Float>.self).pointee
        return SIMD3<Float>(v.x, v.y, 0)
    default:
        return nil
    }
}

// MARK: - Transforms

func transformPosition(_ p: SIMD3<Float>, _ m: float4x4) -> SIMD3<Float> {
    let r = simd_mul(SIMD4<Float>(p, 1), m)
    return SIMD3<Float>(r.x, r.y, r.z)
}

// Mimic the engine's current `Mesh.transformMeshBasis` behavior: it transforms
// direction vectors with w=1 (NOT w=0 as math would dictate). For the engine's
// current basis matrices (which have a zero translation column), w=1 vs w=0
// produces the same result; we faithfully reproduce the engine's behavior for
// fidelity.
func transformDirectionLikeEngine(_ d: SIMD3<Float>, _ m: float4x4) -> SIMD3<Float> {
    let r = simd_mul(SIMD4<Float>(d, 1), m)
    return SIMD3<Float>(r.x, r.y, r.z)
}

// MARK: - Winding analysis

struct WindingReport {
    var aligned: Int = 0
    var opposed: Int = 0
    var degenerate: Int = 0
    var noNormal: Int = 0
    var sampled: Int = 0
}

enum Verdict: String {
    case agreesWithNormals
    case opposesNormals
    case mixed
    case unknown

    static func from(_ r: WindingReport) -> Verdict {
        if r.aligned > 0 && r.opposed == 0 { return .agreesWithNormals }
        if r.opposed > 0 && r.aligned == 0 { return .opposesNormals }
        if r.aligned == 0 && r.opposed == 0 { return .unknown }
        let total = r.aligned + r.opposed
        let dominant = max(r.aligned, r.opposed)
        // Within 5% one way is "consistent" enough to call.
        return Double(dominant) / Double(total) >= 0.95 ? (r.aligned > r.opposed ? .agreesWithNormals : .opposesNormals) : .mixed
    }
}

func analyzeSubmesh(
    mesh: MDLMesh,
    submesh: MDLSubmesh,
    basis: float4x4? = nil,
    sampleLimit: Int = 200
) -> WindingReport {
    var report = WindingReport()

    guard let positionData =
            mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition, as: .float3) ??
            mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition, as: .float4)
    else { return report }

    let normalData =
        mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal, as: .float3) ??
        mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal, as: .float4)

    let triangles = triangleTriples(submesh)
    let stride = max(1, triangles.count / sampleLimit)

    var t = 0
    while t < triangles.count && report.sampled < sampleLimit {
        let (i0, i1, i2) = triangles[t]
        t += stride

        guard
            var p0 = readFloat3(positionData, vertex: i0),
            var p1 = readFloat3(positionData, vertex: i1),
            var p2 = readFloat3(positionData, vertex: i2)
        else { continue }

        if let m = basis {
            p0 = transformPosition(p0, m)
            p1 = transformPosition(p1, m)
            p2 = transformPosition(p2, m)
        }

        let geo = simd_cross(p1 - p0, p2 - p0)
        let geoLen = simd_length(geo)
        if geoLen < 1e-7 { report.degenerate += 1; report.sampled += 1; continue }

        guard let normalData else { report.noNormal += 1; report.sampled += 1; continue }
        guard
            var n0 = readFloat3(normalData, vertex: i0),
            var n1 = readFloat3(normalData, vertex: i1),
            var n2 = readFloat3(normalData, vertex: i2)
        else { report.noNormal += 1; report.sampled += 1; continue }

        if let m = basis {
            n0 = transformDirectionLikeEngine(n0, m)
            n1 = transformDirectionLikeEngine(n1, m)
            n2 = transformDirectionLikeEngine(n2, m)
        }

        let avg = n0 + n1 + n2
        let avgLen = simd_length(avg)
        if avgLen < 1e-7 { report.noNormal += 1; report.sampled += 1; continue }

        let d = simd_dot(geo / geoLen, avg / avgLen)
        if d > 0.1 { report.aligned += 1 }
        else if d < -0.1 { report.opposed += 1 }
        else { report.degenerate += 1 }

        report.sampled += 1
    }

    return report
}

// MARK: - Driver

struct Job {
    let path: String
    let basis: (label: String, matrix: float4x4)?
}

func parseArgs() -> [Job] {
    var jobs: [Job] = []
    var args = Array(CommandLine.arguments.dropFirst())
    var pendingBasis: (String, float4x4)?

    while !args.isEmpty {
        let a = args.removeFirst()
        if a == "--basis" {
            guard !args.isEmpty else {
                fputs("--basis requires a name\n", stderr); exit(2)
            }
            let name = args.removeFirst()
            guard let b = basisNamed(name) else {
                fputs("Unknown basis: \(name). Use one of: none, f22-sketchfab, f22-cgtrader, f18\n", stderr)
                exit(2)
            }
            pendingBasis = b
        } else {
            jobs.append(Job(path: a, basis: pendingBasis))
            pendingBasis = nil
        }
    }
    return jobs
}

func describeBasis(_ b: (label: String, matrix: float4x4)?) -> String {
    guard let b else { return "<none>" }
    let m = b.matrix
    let det3 = simd_determinant(simd_float3x3(
        SIMD3<Float>(m.columns.0.x, m.columns.0.y, m.columns.0.z),
        SIMD3<Float>(m.columns.1.x, m.columns.1.y, m.columns.1.z),
        SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z)
    ))
    return "\(b.label) (3x3 det = \(String(format: "%+.2f", det3)))"
}

func runJob(_ job: Job) {
    print("\n================================================================")
    print("FILE : \(job.path)")
    print("BASIS: \(describeBasis(job.basis))")
    print("================================================================")

    let url = URL(fileURLWithPath: job.path)
    let descriptor = engineVertexDescriptor()
    let allocator = MDLMeshBufferDataAllocator()
    let asset = MDLAsset(url: url, vertexDescriptor: descriptor, bufferAllocator: allocator)

    let meshes = asset.childObjects(of: MDLMesh.self) as? [MDLMesh] ?? []
    guard !meshes.isEmpty else { print("(no meshes)"); return }

    for (mi, mesh) in meshes.enumerated() {
        // Mirror the engine's tangent basis step so the mesh has normals if the
        // source asset omitted them.
        mesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                             normalAttributeNamed: MDLVertexAttributeNormal,
                             tangentAttributeNamed: MDLVertexAttributeTangent)

        let submeshes = mesh.submeshes as? [MDLSubmesh] ?? []
        print("\n  Mesh[\(mi)] '\(mesh.name)'  vertexCount=\(mesh.vertexCount)  submeshes=\(submeshes.count)")

        var meshAligned = 0
        var meshOpposed = 0

        for (si, sm) in submeshes.enumerated() {
            let raw = analyzeSubmesh(mesh: mesh, submesh: sm, basis: nil)
            let post = job.basis.map { analyzeSubmesh(mesh: mesh, submesh: sm, basis: $0.matrix) }

            print("    Submesh[\(si)] '\(sm.name)'  type=\(sm.geometryType.rawValue)  indexCount=\(sm.indexCount)")
            print("      RAW       sampled=\(raw.sampled)  aligned=\(raw.aligned)  opposed=\(raw.opposed)  degenerate=\(raw.degenerate)  noNormal=\(raw.noNormal)  -> \(Verdict.from(raw).rawValue)")
            if let post {
                print("      POST-XFRM sampled=\(post.sampled)  aligned=\(post.aligned)  opposed=\(post.opposed)  degenerate=\(post.degenerate)  noNormal=\(post.noNormal)  -> \(Verdict.from(post).rawValue)")
                meshAligned += post.aligned
                meshOpposed += post.opposed
            } else {
                meshAligned += raw.aligned
                meshOpposed += raw.opposed
            }
        }

        let total = meshAligned + meshOpposed
        if total > 0 {
            let ratio = Double(meshAligned) / Double(total)
            let majority: String = {
                if meshAligned > 0 && meshOpposed == 0 { return "agreesWithNormals" }
                if meshOpposed > 0 && meshAligned == 0 { return "opposesNormals" }
                if ratio >= 0.95 { return "agreesWithNormals" }
                if ratio <= 0.05 { return "opposesNormals" }
                return "mixed"
            }()
            print("    Mesh majority (post-xfrm if applicable): \(majority)  (\(meshAligned) aligned vs \(meshOpposed) opposed)")
        }
    }
}

let jobs = parseArgs()
if jobs.isEmpty {
    fputs("""
    Usage:
      swift inspect_winding.swift <path> [--basis <name>] <path> ...

    Examples:
      swift inspect_winding.swift \\
          "path/F-35A_Lightning_II.usdz" \\
          --basis f22-sketchfab "path/F-22_Raptor.usdz"
    \n
    """, stderr)
    exit(1)
}
for job in jobs { runJob(job) }
