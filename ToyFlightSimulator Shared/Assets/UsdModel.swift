//
//  UsdMesh.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/13/24.
//

import Foundation
import MetalKit

final class UsdModel: Model {
    var skeleton: Skeleton?
    var animationClips: [String: AnimationClip] = [:]
    
    init(_ modelName: String, fileExtension: ModelExtension = .USDZ, transform: float4x4? = nil) {
        guard let assetUrl = Bundle.main.url(forResource: modelName, withExtension: fileExtension.rawValue) else {
            fatalError("Asset \(modelName) does not exist.")
        }
        
        let descriptor = Mesh.createMdlVertexDescriptor()
        let asset = MDLAsset(url: assetUrl,
                             vertexDescriptor: descriptor,
                             bufferAllocator: Mesh.mtkMeshBufferAllocator)
        
        asset.loadTextures()
        
        print("[UsdModel init] \(modelName) asset has \(asset.count) top level objects.")
        
        let mdlMeshes = asset.childObjects(of: MDLMesh.self) as? [MDLMesh] ?? []
        
        // Debugging:
        Self.InspectMeshes(mdlMeshes: mdlMeshes)
        
        let usdMeshes: [Mesh] = Self.GetMeshes(asset: asset, mdlMeshes: mdlMeshes, descriptor: descriptor)
        
        // Invert Z in meshes due to USD being right handed coord system:
//        invertMeshZ()  // Not needed for F-22
        
        super.init(name: modelName, meshes: usdMeshes)
        
        if let transform {
            transformMeshesBasis(transform: transform)
        }
        
        print("[UsdModel init] loading \(modelName) skeleton...")
        self.skeleton = loadSkeleton(asset: asset)
        loadSkins(mdlMeshes: mdlMeshes)
        loadAnimations(asset: asset)
        
        print("[UsdModel init] Num meshes for \(modelName): \(meshes.count)")
    }
    
    private static func InspectMeshes(mdlMeshes: [MDLMesh]) {
        // Debugging:
        for mesh in mdlMeshes {
            print("[UsdModel GetMeshes] > Mesh: name:\(mesh.name), path: \(mesh.path), transform: \(mesh.transform, default: "No Transform")")
            if let submeshes = mesh.submeshes as? [MDLSubmesh] {
                for sm in submeshes {
                    print("[UsdModel GetMeshes] --> Submesh: \(sm.name)")
                }
            }
        }
    }
    
    private func loadSkeleton(asset: MDLAsset) -> Skeleton? {
//        asset.animations
        let skeletons = asset.childObjects(of: MDLSkeleton.self) as? [MDLSkeleton] ?? []
        print("[UsdModel LoadSkeleton] num skeletons: \(skeletons.count)")
//        if let firstSkel = skeletons.first {
//            print("[UsdModel loadSkeleton] first skeleton: \(firstSkel.name), \(firstSkel.jointPaths)")
//        }
        
        for (i, skel) in skeletons.enumerated() {
            print("[UsdModel LoadSkeleton] skeleton [\(i)] name: \(skel.name), jointPaths: \(skel.jointPaths)")
//            skeleton.jointBindTransforms
//            skeleton.jointRestTransforms
        }
        
        // TODO: Only taking into account first skeleton:
        return Skeleton(mdlSkeleton: skeletons.first)
    }
    
    private func loadSkins(mdlMeshes: [MDLMesh]) {
        for index in 0..<mdlMeshes.count {
            let animationBindComponent = mdlMeshes[index].componentConforming(to: MDLComponent.self)
                as? MDLAnimationBindComponent
            
            print("[UsdModel LoadSkins] mesh index: \(index), animationBindComponent: \(String(describing: animationBindComponent))")
            
            guard let skeleton else { continue }
            
            let skin = Skin(animationBindComponent: animationBindComponent, skeleton: skeleton)
            meshes[index].skin = skin
        }
    }
    
    private func loadAnimations(asset: MDLAsset) {
        let assetAnimations = asset.animations.objects.compactMap { $0 as? MDLPackedJointAnimation }
        for assetAnimation in assetAnimations {
            print("[UsdModel LoadAnimations] assetAnimation name: \(assetAnimation.name), path: \(assetAnimation.path), jointPaths: \(assetAnimation.jointPaths)")
            let animationClip = AnimationClip(animation: assetAnimation)
            animationClips[assetAnimation.name] = animationClip
        }
    }
    
    // TODO: Parallelize this:
    private func transformMeshesBasis(transform: float4x4) {
        for mesh in meshes {
            let vertexBuffer = mesh.vertexBuffer!
            let count = vertexBuffer.length / Vertex.stride
            var pointer = vertexBuffer.contents().bindMemory(to: Vertex.self, capacity: count)
            for _ in 0..<count {
                pointer.pointee.position = simd_mul(float4(pointer.pointee.position, 1), transform).xyz
                pointer.pointee.normal = simd_mul(float4(pointer.pointee.normal, 1), transform).xyz
                pointer.pointee.tangent = simd_mul(float4(pointer.pointee.tangent, 1), transform).xyz
                pointer.pointee.bitangent = simd_mul(float4(pointer.pointee.bitangent, 1), transform).xyz
                pointer = pointer.advanced(by: 1)
            }
        }
    }
    
    private func invertMeshZ() {
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
    
    override func update() {
        let currentTime = Float(GameTime.TotalGameTime)
        
        if let skeleton,
           let animation = animationClips.first {
            print("[UsdModel update] Updating animation clip \(animation.key) & pose for \(self.name)")
            let animationClip = animation.value
            skeleton.updatePose(at: currentTime, animationClip: animationClip)
        }
        
        // TODO: Can this go inside the if let above ???
        for index in 0..<meshes.count {
            var mesh = meshes[index]
            mesh.transform?.getCurrentTransform(at: currentTime)
            mesh.skin?.updatePalette(skeleton: skeleton)
            meshes[index] = mesh
        }
    }
}
