//
//  Model.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/13/24.
//

import MetalKit

enum ModelExtension: String {
    case OBJ = "obj"
    case USDC = "usdc"
    case USDZ = "usdz"
}

class Model: Hashable {
    public let id: String
    public let name: String

    /// Source ModelIO representation, kept for CPU-side access to the imported
    /// geometry (nil for procedural models assembled from pre-built meshes).
    ///
    /// NOTE: Retaining `asset`/`mdlMeshes` (and each `Mesh.mdlMesh`) keeps the full
    /// ModelIO representation — including texture data pulled in by `loadTextures()` —
    /// resident for the lifetime of the cached Model, and an extracted
    /// `SingleSubmeshMesh` pins its shared parent MDLMesh even after
    /// `clearCachedSourceModels()` releases the parent asset. Future refactor:
    /// release these once consumers have extracted what they need (or store only
    /// the extracted data) if memory pressure becomes a problem, especially on iOS.
    public let asset: MDLAsset?
    public let mdlMeshes: [MDLMesh]
    public var meshes: [Mesh] = []
    
    /// Stored basis transform for coordinate system conversion (passed to Skeleton for animation)
    public let basisTransform: float4x4

    static func == (lhs: Model, rhs: Model) -> Bool {
        return lhs.id == rhs.id
    }
    
    static func GetMeshes(asset: MDLAsset,
                          mdlMeshes: [MDLMesh],
                          descriptor: MDLVertexDescriptor,
                          basisTransform: float4x4? = nil) -> [Mesh] {
        return mdlMeshes.map { Mesh(asset: asset,
                                    mdlMesh: $0,
                                    vertexDescriptor: descriptor,
                                    basisTransform: basisTransform) }
    }
    
    static func LoadAsset(_ modelName: String,
                          fileExtension: ModelExtension,
                          descriptor: MDLVertexDescriptor) -> MDLAsset {
        guard let assetUrl = Bundle.main.url(forResource: modelName, withExtension: fileExtension.rawValue) else {
            fatalError("Asset \(modelName) does not exist.")
        }
        
        let asset = MDLAsset(url: assetUrl,
                             vertexDescriptor: descriptor,
                             bufferAllocator: Mesh.mtkMeshBufferAllocator)

        asset.loadTextures()
        return asset
    }
    
    /// Extent of the model along the engine's forward axis (+Z) after `basisTransform`.
    /// Aircraft bases map the model's nose-to-tail axis onto ±Z (aircraft face +Z in
    /// this engine), so this is the aircraft's length. Row-vector `v * B`, matching
    /// `Mesh.transformMeshBasis`; w = 0 because an extent is a size, not a point — a
    /// translation-bearing basis must not offset it.
    static func GetLengthAxisExtent(nativeExtent: simd_float3, basisTransform: float4x4? = nil) -> Float {
        let transformedExtent: float3 = (simd_float4(nativeExtent, 0) * (basisTransform ?? .identity)).xyz
        return abs(transformedExtent.z)
    }
    
    /// `basisTransform` stays optional end-to-end: `nil` means "no basis conversion",
    /// which lets `Mesh.init` skip the per-vertex transform pass entirely instead of
    /// multiplying every vertex by identity.
    init(_ modelName: String, fileExtension: ModelExtension, basisTransform: float4x4? = nil, realWorldLength: Float? = nil) {
        let descriptor = Mesh.createMdlVertexDescriptor()

        let loadedAsset = Self.LoadAsset(modelName, fileExtension: fileExtension, descriptor: descriptor)

        print("[Model init] \(modelName) asset has \(loadedAsset.count) top level objects.")
        
        let meterizedBasisTransform: float4x4?
        
        if let realWorldLength {
            let nativeExtent = loadedAsset.boundingBox.maxBounds - loadedAsset.boundingBox.minBounds
            let nativeLength = Self.GetLengthAxisExtent(nativeExtent: nativeExtent, basisTransform: basisTransform)
            precondition(nativeLength > 0.001,
                         "[Model init] \(modelName): degenerate native length \(nativeLength) — cannot meterize")
            let scaleCorrection = realWorldLength / nativeLength
            // Uniform scale: det(s·B) = s³·det(B) keeps the sign, so the winding decision in
            // Mesh.transformMeshBasis is unchanged; shaders renormalize the scaled normals.
            meterizedBasisTransform = Transform.scaleMatrix(float3(repeating: scaleCorrection)) * (basisTransform ?? .identity)
            DebugLog("[Model init] Model \(modelName) is \(realWorldLength)m long (native: \(nativeLength)m, scale correction: \(scaleCorrection))", true)
        } else {
            meterizedBasisTransform = basisTransform
        }

        let mdlMeshes = loadedAsset.childObjects(of: MDLMesh.self) as? [MDLMesh] ?? []

        Self.InspectMeshes(mdlMeshes: mdlMeshes)

        self.asset = loadedAsset
        self.mdlMeshes = mdlMeshes
        self.meshes = Self.GetMeshes(asset: loadedAsset,
                                     mdlMeshes: mdlMeshes,
                                     descriptor: descriptor,
                                     basisTransform: meterizedBasisTransform)

        self.id = UUID().uuidString
        self.name = modelName
        self.basisTransform = meterizedBasisTransform ?? .identity
        meshes.forEach { $0.parentModel = self }
    }
    
    init(name: String, meshes: [Mesh], basisTransform: float4x4 = .identity) {
        self.id = UUID().uuidString
        self.name = name
        self.asset = nil  // Procedural models have no source ModelIO asset
        self.meshes = meshes
        self.mdlMeshes = meshes.compactMap { $0.mdlMesh }
        self.basisTransform = basisTransform
        meshes.forEach { $0.parentModel = self }
    }
    
    convenience init(name: String, mesh: Mesh, basisTransform: float4x4 = .identity) {
        self.init(name: name, meshes: [mesh], basisTransform: basisTransform)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }
    
    // TODO: might want to refactor this...
    // Override this in UsdModel for now...
    public func update() { }
    
    // Invert Z in meshes due to USD being right handed coord system:
    // NOTE: Ordinarily this should not be needed, originally created
    //       because some USD files were created in a right hand coord sys
    //       and Metal uses a left hand coord sys.
    func invertMeshZ() {
        for mesh in meshes {
            let vertexBuffer = mesh.vertexBuffer!
            let count = vertexBuffer.length / Vertex.stride
            var pointer = vertexBuffer.contents().bindMemory(to: Vertex.self, capacity: count)
            for _ in 0..<count {
                pointer.pointee.position.z = -pointer.pointee.position.z
                pointer = pointer.advanced(by: 1)
            }
        }
    }
    
    static func InspectMeshes(mdlMeshes: [MDLMesh]) {
        for mesh in mdlMeshes {
            DebugLog("[Model InspectMeshes] > Mesh: name:\(mesh.name), path: \(mesh.path), transform: \(mesh.transform, default: "No Transform")", DEBUG_MESH_INSPECTION)
            if let submeshes = mesh.submeshes as? [MDLSubmesh] {
                for sm in submeshes {
                    DebugLog("[Model InspectMeshes] --> Submesh: \(sm.name)", DEBUG_MESH_INSPECTION)
                }
            }
        }
    }
}
