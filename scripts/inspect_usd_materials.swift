import Foundation
import ModelIO
import MetalKit

func inspect(_ path: String) {
    let url = URL(fileURLWithPath: path)
    print("\n=== Inspecting: \(url.path) ===")

    let device = MTLCreateSystemDefaultDevice()!
    let allocator = MTKMeshBufferAllocator(device: device)

    let descriptor = MDLVertexDescriptor()
    let asset = MDLAsset(url: url, vertexDescriptor: descriptor, bufferAllocator: allocator)
    asset.loadTextures()

    let meshes = asset.childObjects(of: MDLMesh.self) as? [MDLMesh] ?? []
    print("Meshes: \(meshes.count)")

    for (mi, mesh) in meshes.enumerated() {
        print("Mesh[\(mi)] name=\(mesh.name) submeshes=\(mesh.submeshes?.count ?? 0)")
        guard let submeshes = mesh.submeshes as? [MDLSubmesh] else { continue }
        for (si, sm) in submeshes.enumerated() {
            print("  Submesh[\(si)] name=\(sm.name)")
            guard let mat = sm.material else {
                print("    material: nil")
                continue
            }
            let base = mat.property(with: .baseColor)
            let norm = mat.property(with: .tangentSpaceNormal)
            let metal = mat.property(with: .metallic)
            print("    material=\(mat.name)")
            func describe(_ label: String, _ prop: MDLMaterialProperty?) {
                guard let prop else {
                    print("    \(label): <nil>")
                    return
                }
                print("    \(label): type=\(prop.type.rawValue) semantic=\(prop.semantic.rawValue)")
                if let s = prop.stringValue { print("      string=\(s)") }
                if let u = prop.urlValue { print("      url=\(u.path)") }
                if let sampler = prop.textureSamplerValue, let tex = sampler.texture {
                    print("      texture=\(tex.name) size=\(tex.dimensions.x)x\(tex.dimensions.y)")
                }
            }
            describe("baseColor", base)
            describe("normal", norm)
            describe("metallic", metal)
        }
    }
}

let args = CommandLine.arguments.dropFirst()
if args.isEmpty {
    fputs("Usage: inspect_usd_materials <usdc-path> [<usdc-path> ...]\n", stderr)
    exit(1)
}
for arg in args { inspect(arg) }
