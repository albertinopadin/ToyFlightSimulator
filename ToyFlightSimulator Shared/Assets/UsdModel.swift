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

    /// Flag indicating whether this model has an external animator controlling its animations.
    /// When true, the model's update() method will not drive animations automatically.
    var hasExternalAnimator: Bool = false
    
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
        
        printAllMeshTransformDurations()

        // Initialize to the end of the animation (gear down position)
        // This ensures models start in a sensible default pose
        initializeAnimationPose(at: animationDuration)
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
        print("[UsdModel loadSkeletons] Number of animations in asset \(String(describing: asset.url)): \(asset.animations.count)")
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
            // Testing:
            if mdlMeshes[index].components.count > 1 || mdlMeshes[index].children.count > 1 {
                print("[UsdModel loadSkins] Model \(self.name) > Number of components in mesh \(index): \(mdlMeshes[index].components.count)")
                print("[UsdModel loadSkins] Model \(self.name) > Number of children in mesh \(index): \(mdlMeshes[index].children.count)")
                
                for component in mdlMeshes[index].components {
                    print("[UsdModel loadSkins] Model \(self.name) > mesh \(index), Component: \(component)")
                }
            }
            
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
            
            if meshSkeletonMap[index] != nil {
                print("[UsdModel loadSkins] Warning: Overwriting existing mesh-to-skeleton mapping for mesh[\(index)]")
            }
            
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
            print("[UsdModel loadAnimations] Animation named '\(animationName)': path=\(assetAnimation.path), jointPaths=\(animationJointPaths)")

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
    
    private func printAllMeshTransformDurations() {
        for (i, mesh) in meshes.enumerated() {
            if let transform = mesh.transform {
                print("[UsdModel t.duration] \(i)th mesh \(mesh.name) duration: \(transform.duration)")
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
        // If an external animator (like AircraftAnimator) is controlling this model,
        // skip the built-in animation update. The animator will call updatePose directly.
        guard !hasExternalAnimator else { return }

        // For models without external animators, animations remain at their initial pose
        // (set by initializeAnimationPose during init)
    }

    /// Initializes all skeletons and meshes to a specific animation time.
    /// Called during init to set the initial pose (e.g., gear down at animation end).
    /// - Parameter time: The animation time to set (0 = start, duration = end)
    func initializeAnimationPose(at time: Float) {
        // Update all skeletons with their respective animation clips
        for (skeletonPath, skeleton) in skeletons {
            if let animationName = skeletonAnimationMap[skeletonPath],
               let animationClip = animationClips[animationName] {
                skeleton.updatePose(at: time, animationClip: animationClip)
            } else if let firstClip = animationClips.values.first {
                skeleton.updatePose(at: time, animationClip: firstClip)
            }
        }

        // Update each mesh's transform and skin
        for (index, mesh) in meshes.enumerated() {
            if mesh.transform != nil {
                mesh.transform?.setCurrentTransform(at: time)
            }

            if let skeletonPath = meshSkeletonMap[index],
               let skeleton = skeletons[skeletonPath] {
                mesh.skin?.updatePalette(skeleton: skeleton)
            } else if skeletons.count == 1, let onlySkeleton = skeletons.values.first {
                mesh.skin?.updatePalette(skeleton: onlySkeleton)
            }
        }
    }

    /// Returns the total animation duration (from the first animation clip)
    var animationDuration: Float {
        return animationClips.values.first?.duration ?? 0
    }
}
