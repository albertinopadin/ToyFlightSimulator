//
//  UsdMesh.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/13/24.
//

import Foundation
import MetalKit

final class UsdModel: Model {
    /// All skeletons in the asset, keyed by their path
    var skeletons: [String: Skeleton] = [:]

    /// Maps each mesh index to its skeleton's path (for meshes that have skeletal animation)
    var meshSkeletonMap: [Int: String] = [:]

    /// Animation clips, keyed by their name
    var animationClips: [String: AnimationClip] = [:]

    /// Maps skeleton paths to their associated animation clip names
    var skeletonAnimationMap: [String: String] = [:]

    /// Stored basis transform for coordinate system conversion (passed to Skeleton for animation)
    private let basisTransform: float4x4?

    init(_ modelName: String, fileExtension: ModelExtension = .USDZ, basisTransform: float4x4? = nil) {
        self.basisTransform = basisTransform
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

        let usdMeshes: [Mesh] = Self.GetMeshes(asset: asset,
                                               mdlMeshes: mdlMeshes,
                                               descriptor: descriptor,
                                               basisTransform: basisTransform)

        super.init(name: modelName, meshes: usdMeshes)

        // Invert Z in meshes due to USD being right handed coord system:
//        invertMeshZ()   // Not needed for F-22

        print("[UsdModel init] loading \(modelName) skeletons...")
        loadSkeletons(asset: asset)
        loadSkins(mdlMeshes: mdlMeshes)
        loadAnimations(asset: asset)

        print("[UsdModel init] Num meshes: \(meshes.count), Num skeletons: \(skeletons.count), Num animations: \(animationClips.count)")
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
    
    /// Loads ALL skeletons from the asset into the skeletons dictionary, keyed by path
    private func loadSkeletons(asset: MDLAsset) {
        let mdlSkeletons = asset.childObjects(of: MDLSkeleton.self) as? [MDLSkeleton] ?? []
        print("[UsdModel loadSkeletons] Found \(mdlSkeletons.count) skeletons")

        for (i, mdlSkeleton) in mdlSkeletons.enumerated() {
            let skeletonPath = mdlSkeleton.path
            print("[UsdModel loadSkeletons] skeleton [\(i)] path: \(skeletonPath), name: \(mdlSkeleton.name), jointPaths: \(mdlSkeleton.jointPaths)")

            // Create a Skeleton for each MDLSkeleton, passing basisTransform for coordinate system conversion
            if let skeleton = Skeleton(mdlSkeleton: mdlSkeleton, basisTransform: basisTransform) {
                skeletons[skeletonPath] = skeleton
                print("[UsdModel loadSkeletons] Created skeleton for path: \(skeletonPath)")
            }
        }
    }

    /// Helper to find a skeleton by matching joint paths (used when MDLAnimationBindComponent.skeleton is nil)
    private func findSkeletonByJointPaths(_ jointPaths: [String]) -> (path: String, skeleton: Skeleton)? {
        // Try to find a skeleton that contains all the joint paths
        for (path, skeleton) in skeletons {
            let matchCount = jointPaths.filter { skeleton.jointPaths.contains($0) }.count
            if matchCount == jointPaths.count {
                return (path, skeleton)
            }
        }

        // If no exact match, find the skeleton with the most matching joints
        var bestMatch: (path: String, skeleton: Skeleton, matchCount: Int)?
        for (path, skeleton) in skeletons {
            let matchCount = jointPaths.filter { skeleton.jointPaths.contains($0) }.count
            if matchCount > 0 && (bestMatch == nil || matchCount > bestMatch!.matchCount) {
                bestMatch = (path, skeleton, matchCount)
            }
        }

        if let best = bestMatch {
            return (best.path, best.skeleton)
        }
        return nil
    }
    
    private func loadSkins(mdlMeshes: [MDLMesh]) {
        for index in 0..<mdlMeshes.count {
            let animationBindComponent = mdlMeshes[index].componentConforming(to: MDLComponent.self)
                as? MDLAnimationBindComponent

            guard let animationBindComponent else {
                print("[UsdModel loadSkins] mesh[\(index)] '\(mdlMeshes[index].name)': No animationBindComponent")
                continue
            }

            // Get the skeleton that this mesh is bound to
            var skeletonPath: String?
            var skeleton: Skeleton?

            // First, try to get the skeleton directly from the animationBindComponent
            if let mdlSkeleton = animationBindComponent.skeleton {
                skeletonPath = mdlSkeleton.path
                skeleton = skeletons[skeletonPath!]
                print("[UsdModel loadSkins] mesh[\(index)] '\(mdlMeshes[index].name)': Found skeleton via animationBindComponent.skeleton: \(skeletonPath!)")
            }

            // If animationBindComponent.skeleton is nil, try to match by joint paths
            if skeleton == nil, let jointPaths = animationBindComponent.jointPaths, !jointPaths.isEmpty {
                if let match = findSkeletonByJointPaths(jointPaths) {
                    skeletonPath = match.path
                    skeleton = match.skeleton
                    print("[UsdModel loadSkins] mesh[\(index)] '\(mdlMeshes[index].name)': Found skeleton by jointPath matching: \(skeletonPath!)")
                }
            }

            // Fallback: use the first skeleton if only one exists
            if skeleton == nil && skeletons.count == 1, let firstSkeleton = skeletons.first {
                skeletonPath = firstSkeleton.key
                skeleton = firstSkeleton.value
                print("[UsdModel loadSkins] mesh[\(index)] '\(mdlMeshes[index].name)': Using only available skeleton: \(skeletonPath!)")
            }

            guard let skeleton, let skeletonPath else {
                print("[UsdModel loadSkins] mesh[\(index)] '\(mdlMeshes[index].name)': Could not find matching skeleton")
                continue
            }

            // Create the skin and record the mesh-to-skeleton mapping
            let skin = Skin(animationBindComponent: animationBindComponent, skeleton: skeleton)
            meshes[index].skin = skin
            meshSkeletonMap[index] = skeletonPath
            print("[UsdModel loadSkins] mesh[\(index)] '\(mdlMeshes[index].name)': Created skin with skeleton '\(skeletonPath)'")
        }
    }
    
    private func loadAnimations(asset: MDLAsset) {
        let assetAnimations = asset.animations.objects.compactMap { $0 as? MDLPackedJointAnimation }
        print("[UsdModel loadAnimations] Found \(assetAnimations.count) animations")

        for assetAnimation in assetAnimations {
            let animationName = assetAnimation.name
            let animationJointPaths = assetAnimation.jointPaths
            print("[UsdModel loadAnimations] Animation '\(animationName)': path=\(assetAnimation.path), jointPaths=\(animationJointPaths)")

            let animationClip = AnimationClip(animation: assetAnimation)
            animationClips[animationName] = animationClip

            // Associate this animation with the skeleton that has matching joint paths
            if let match = findSkeletonByJointPaths(animationJointPaths) {
                skeletonAnimationMap[match.path] = animationName
                print("[UsdModel loadAnimations] Animation '\(animationName)' associated with skeleton '\(match.path)'")
            } else {
                print("[UsdModel loadAnimations] Animation '\(animationName)': Could not find matching skeleton")

                // Fallback: if only one skeleton exists, associate with it
                if skeletons.count == 1, let firstSkeleton = skeletons.first {
                    skeletonAnimationMap[firstSkeleton.key] = animationName
                    print("[UsdModel loadAnimations] Animation '\(animationName)' associated with only skeleton '\(firstSkeleton.key)'")
                }
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

        // Update ALL skeletons with their respective animation clips
        for (skeletonPath, skeleton) in skeletons {
            // Find the animation clip associated with this skeleton
            if let animationName = skeletonAnimationMap[skeletonPath],
               let animationClip = animationClips[animationName] {
                skeleton.updatePose(at: currentTime, animationClip: animationClip)
            } else if let firstClip = animationClips.values.first {
                // Fallback: use the first animation clip if no specific association exists
                skeleton.updatePose(at: currentTime, animationClip: firstClip)
            }
        }

        // Update each mesh with its own skeleton
        for index in 0..<meshes.count {
            var mesh = meshes[index]

            // Update TransformComponent animation (non-skeletal mesh animation)
            mesh.transform?.setCurrentTransform(at: currentTime)

            // Update skin with the CORRECT skeleton for this mesh
            if let skeletonPath = meshSkeletonMap[index],
               let skeleton = skeletons[skeletonPath] {
                mesh.skin?.updatePalette(skeleton: skeleton)
            } else if skeletons.count == 1, let onlySkeleton = skeletons.values.first {
                // Fallback: if only one skeleton exists, use it
                mesh.skin?.updatePalette(skeleton: onlySkeleton)
            }

            meshes[index] = mesh
        }
    }
}
