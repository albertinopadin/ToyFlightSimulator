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

    /// The native-space extent the renderer will actually draw (before `basisTransform`):
    /// the union, over the asset's meshes, of each MESH-LOCAL bounding box carried through
    /// that mesh's scale-stripped composed node transform.
    ///
    /// `MDLAsset.boundingBox` is the wrong measurement space for meterization: it composes
    /// the full node-hierarchy transforms INCLUDING scale, but the engine bakes mesh-local
    /// vertex data (`Mesh.transformMeshBasis`) and applies node transforms at draw time
    /// with the scale stripped (`TransformComponent` — `GameObject.setScale()` is the sole
    /// source of gameplay scale). Sketchfab exports carry root node scales (F-22 Raptor
    /// ×5.78, F-35A ×15.03) that made the stage-space measurement over-report the native
    /// length — and the meterized aircraft rendered smaller by exactly that factor. See
    /// debugging/claude/sketchfab_f22_f35_meterization_node_scale.md.
    ///
    /// A mesh's node transform participates exactly when the renderer would apply it: the
    /// mesh has a transform component AND the asset is animated —
    /// `TransformComponent.setCurrentTransform` leaves `currentTransform` at identity when
    /// the asset time range is empty (the Sketchfab F-22 is such an asset: its node
    /// transforms exist but never apply at draw).
    static func DrawSpaceNativeExtent(asset: MDLAsset, mdlMeshes: [MDLMesh]) -> simd_float3 {
        let nodeTransformsApplyAtDraw = asset.endTime > asset.startTime
        let meshBounds: [(minBounds: float3, maxBounds: float3, nodeTransform: float4x4)] = mdlMeshes.map { mesh in
            let bounds = mesh.boundingBox
            let nodeTransform: float4x4 = (nodeTransformsApplyAtDraw && mesh.transform != nil)
                ? Transform.scaleStrippedTransform(MDLTransform.globalTransform(with: mesh, atTime: asset.startTime))
                : .identity
            return (bounds.minBounds, bounds.maxBounds, nodeTransform)
        }
        return UnionTransformedExtent(meshBounds: meshBounds)
    }

    /// Union AABB extent of local bounds each carried through its own node transform
    /// (column-vector ModelIO convention, `p' = M · p`). Pure simd — Metal-free and
    /// unit-testable (ModelMeterizationTests).
    static func UnionTransformedExtent(meshBounds: [(minBounds: float3, maxBounds: float3, nodeTransform: float4x4)]) -> simd_float3 {
        guard !meshBounds.isEmpty else { return .zero }
        var unionMin = float3(repeating: .greatestFiniteMagnitude)
        var unionMax = float3(repeating: -.greatestFiniteMagnitude)
        for (minBounds, maxBounds, nodeTransform) in meshBounds {
            for cornerIndex in 0..<8 {
                let corner = float3(cornerIndex & 1 == 0 ? minBounds.x : maxBounds.x,
                                    cornerIndex & 2 == 0 ? minBounds.y : maxBounds.y,
                                    cornerIndex & 4 == 0 ? minBounds.z : maxBounds.z)
                let transformed = simd_mul(nodeTransform, float4(corner, 1)).xyz
                unionMin = simd_min(unionMin, transformed)
                unionMax = simd_max(unionMax, transformed)
            }
        }
        return unionMax - unionMin
    }
    
    /// `basisTransform` stays optional end-to-end: `nil` means "no basis conversion",
    /// which lets `Mesh.init` skip the per-vertex transform pass entirely instead of
    /// multiplying every vertex by identity.
    init(_ modelName: String, fileExtension: ModelExtension, basisTransform: float4x4? = nil, realWorldLength: Float? = nil) {
        let descriptor = Mesh.createMdlVertexDescriptor()

        let loadedAsset = Self.LoadAsset(modelName, fileExtension: fileExtension, descriptor: descriptor)

        DebugLog("[Model init] \(modelName) asset has \(loadedAsset.count) top level objects.", true)
        
        let mdlMeshes = loadedAsset.childObjects(of: MDLMesh.self) as? [MDLMesh] ?? []

        let meterizedBasisTransform: float4x4?

        if let realWorldLength {
            // Draw-space, NOT loadedAsset.boundingBox (stage space): the renderer strips
            // node-hierarchy scale, so calibration must measure what is actually drawn.
            let nativeExtent = Self.DrawSpaceNativeExtent(asset: loadedAsset, mdlMeshes: mdlMeshes)
            let nativeLength = Self.GetLengthAxisExtent(nativeExtent: nativeExtent, basisTransform: basisTransform)
            precondition(nativeLength > 0.001,
                         "[Model init] \(modelName): degenerate native length \(nativeLength) — cannot meterize")
            let scaleCorrection = realWorldLength / nativeLength
            // Uniform scale: det(s·B) = s³·det(B) keeps the sign, so the winding decision in
            // Mesh.transformMeshBasis is unchanged; shaders renormalize the scaled normals.
            let scaleCorrectionTransform = Transform.scaleMatrix(float3(repeating: scaleCorrection))
            meterizedBasisTransform = scaleCorrectionTransform * (basisTransform ?? .identity)
            DebugLog("[Model init] Model \(modelName) is \(realWorldLength)m long (native: \(nativeLength)m, scale correction: \(scaleCorrection)), result: \(nativeLength * scaleCorrection)", true)
        } else {
            meterizedBasisTransform = basisTransform
        }

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
