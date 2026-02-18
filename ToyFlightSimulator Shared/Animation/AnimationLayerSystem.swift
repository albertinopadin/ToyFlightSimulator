//
//  AnimationLayerSystem.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/13/26.
//

import Foundation

/// Manages multiple animation layers and coordinates pose updates.
/// Each layer controls a specific animatable subsystem (landing gear, flaps, etc.)
/// and the layer system ensures only dirty layers trigger pose recalculations.
final class AnimationLayerSystem {
    // MARK: - Properties

    /// Reference to the model containing animation data (skeletons, clips, skins)
    private weak var model: UsdModel?

    /// Registered animation layers, keyed by their unique ID
    private var layers: [String: AnimationLayer] = [:]
    
    private var layerSets: [String: AnimationLayerSet] = [:]

    /// Order in which layers are evaluated (for deterministic updates)
    private var evaluationOrder: [String] = []
    
    private var layerSetEvaluationOrder: [String] = []

    /// Whether debug logging is enabled
    var debugLogging: Bool = true

    // MARK: - Computed Properties

    /// All registered layer IDs
    var layerIDs: [String] {
        Array(layers.keys)
    }

    /// Number of registered layers
    var layerCount: Int {
        layers.count
    }

    /// Whether any layer is currently dirty (needs pose update)
    var hasDirtylayers: Bool {
        layers.values.contains { $0.isDirty }
    }

    // MARK: - Initialization

    /// Creates a new animation layer system for a model
    /// - Parameter model: The UsdModel containing skeletons, animation clips, and skins
    init(model: UsdModel) {
        self.model = model
        model.hasExternalAnimator = true

        if debugLogging {
            print("[AnimationLayerSystem] Initialized for model: \(model.name)")
            print("[AnimationLayerSystem] \(model.skeletons.count) Available skeletons: \(model.skeletons.keys)")
            print("[AnimationLayerSystem] \(model.animationClips.count) Available clips: \(model.animationClips.keys)")
        }
    }

    // MARK: - layer Management

    /// Register a new animation layer
    /// - Parameter layer: The layer to register
    func registerlayer(_ layer: AnimationLayer) {
        let id = layer.id

        if layers[id] != nil {
            print("[AnimationLayerSystem] Warning: Replacing existing layer '\(id)'")
            evaluationOrder.removeAll { $0 == id }
        }

        layers[id] = layer
        evaluationOrder.append(id)

        // If layer doesn't have an animation clip assigned, try to find a matching one
        if layer.animationClip == nil, let model = model {
            // Try to find a clip that might match this layer
            if let firstClip = model.animationClips.values.first {
                layer.animationClip = firstClip
            }
        }

        if debugLogging {
            print("[AnimationLayerSystem] Registered layer '\(id)' with mask: \(layer.mask)")
        }
    }

    /// Unregister a layer by its ID
    /// - Parameter id: The layer ID to remove
    func unregisterlayer(_ id: String) {
        layers.removeValue(forKey: id)
        evaluationOrder.removeAll { $0 == id }

        if debugLogging {
            print("[AnimationLayerSystem] Unregistered layer '\(id)'")
        }
    }

    /// Get a layer by its ID
    /// - Parameter id: The layer ID
    /// - Returns: The layer if found, nil otherwise
    func layer(_ id: String) -> AnimationLayer? {
        layers[id]
    }

    /// Get a typed layer by its ID
    /// - Parameters:
    ///   - id: The layer ID
    ///   - type: The expected layer type
    /// - Returns: The layer cast to the specified type, or nil if not found or wrong type
    func layer<T: AnimationLayer>(_ id: String, as type: T.Type) -> T? {
        layers[id] as? T
    }

    /// Check if a layer with the given ID exists
    /// - Parameter id: The layer ID to check
    /// - Returns: True if the layer exists
    func haslayer(_ id: String) -> Bool {
        layers[id] != nil
    }
    
    /// Register a new animation layer set
    /// - Parameter layerSet: The layer set to register
    func registerlayerSet(_ layerSet: AnimationLayerSet) {
        let id = layerSet.id

        if layerSets[id] != nil {
            print("[AnimationLayerSystem] Warning: Replacing existing layer set '\(id)'")
            layerSetEvaluationOrder.removeAll { $0 == id }
        }

        layerSets[id] = layerSet
        layerSetEvaluationOrder.append(id)

        if debugLogging {
//            print("[AnimationLayerSystem] Registered layer set '\(id)' with mask: \(layer.mask)")
            print("[AnimationLayerSystem] Registered layer set '\(id)'")
        }
    }
    
    func layerSet(_ id: String) -> AnimationLayerSet? {
        return layerSets[id]
    }
    
    func haslayerSet(_ id: String) -> Bool {
        layerSets[id] != nil
    }

    // MARK: - Update

    /// Update all layers and refresh poses for any that changed
    /// - Parameter deltaTime: Time since last update in seconds
//    func update(deltaTime: Float) {
//        guard let model = model else { return }
//
//        // Update all layer state machines
//        for id in evaluationOrder {
//            layers[id]?.update(deltaTime: deltaTime)
//        }
//
//        // Update poses for dirty layers
//        for id in evaluationOrder {
//            guard let layer = layers[id], layer.isDirty else { continue }
//
//            if debugLogging {
//                print("[AnimationLayerSystem] Updating poses for dirty layer '\(id)'")
//            }
//
//            updatePoses(for: layer, model: model)
//            layer.clearDirty()
//        }
//    }
    
    func update(deltaTime: Float) {
        guard let model = model else { return }

        // Update all layer state machines
        for id in layerSetEvaluationOrder {
            layerSets[id]?.update(deltaTime: deltaTime)
        }

        // Update poses for dirty layers
        for id in layerSetEvaluationOrder {
            if let layerSet = layerSets[id] {
                for layer in layerSet.layers {
                    guard layer.isDirty else { continue }
                    
                    if debugLogging {
                        print("[AnimationLayerSystem] Updating poses for dirty layer '\(layer.id)'")
                    }
                    
                    updatePoses(for: layer, model: model)
                    layer.clearDirty()
                }
            }
        }
    }

    // MARK: - Pose Updates

    /// Update skeleton and mesh poses for a single layer
    /// - Parameters:
    ///   - layer: The layer to update poses for
    ///   - model: The model containing animation data
    private func updatePoses(for layer: AnimationLayer, model: UsdModel) {
        let animTime = layer.getAnimationTime()
        let mask = layer.mask

        if debugLogging {
            print("[AnimationLayerSystem] layer '\(layer.id)' animation time: \(animTime)")
        }

        // Determine which skeletons are affected by this layer's mask
        var affectedSkeletonPaths: Set<String> = []

        for (skeletonPath, skeleton) in model.skeletons {
            // Check if any joints in this skeleton are in the layer mask
            let hasAffectedJoints = skeleton.jointPaths.contains { mask.contains(jointPath: $0) }

            if hasAffectedJoints || mask.jointPaths.isEmpty {
                // If mask has no joints specified, it affects all (for backward compatibility)
                affectedSkeletonPaths.insert(skeletonPath)

                // Find the animation clip to use
                let clip = layer.animationClip
                    ?? model.animationClips[model.skeletonAnimationMap[skeletonPath] ?? ""]
                    ?? model.animationClips.values.first

                if let clip = clip {
                    skeleton.updatePose(at: animTime, animationClip: clip)

                    if debugLogging {
                        print("[AnimationLayerSystem] Updated skeleton '\(skeletonPath)' at time \(animTime)")
                    }
                }
            }
        }

        // Update mesh transforms and skins for affected meshes
        for (index, mesh) in model.meshes.enumerated() {
            // TODO: Make this code work so this is efficient and actually targets the correct meshes:
            
            // Check if this mesh is directly affected by the mask
            let meshDirectlyAffected = mask.contains(meshIndex: index)

            // Check if this mesh's skeleton is affected
            var meshSkeletonAffected = false
            if let skeletonPath = model.meshSkeletonMap[index] {
                meshSkeletonAffected = affectedSkeletonPaths.contains(skeletonPath) ||
                                        model.meshSkeletonMap[index] == skeletonPath
                
            }

            // Skip if this mesh is not affected
            guard meshDirectlyAffected || meshSkeletonAffected || mask.isEmpty || mesh.transform != nil else {
                print("[AnimationLayerSystem updatePose] Skipping mesh \(index) as it is not affected by the animation")
                continue
            }

            // Update transform component if present (for non-skeletal mesh animation)
            if mesh.transform != nil {
                print("[AnimationLayerSystem] Set mesh \(index) transform at time \(animTime)")
                mesh.transform!.setCurrentTransform(at: animTime)
            }

            // Update skin with skeleton pose
            if let skeletonPath = model.meshSkeletonMap[index],
               let skeleton = model.skeletons[skeletonPath] {
                mesh.skin?.updatePalette(skeleton: skeleton)
                if debugLogging {
                    print("[AnimationLayerSystem] Updated mesh skin palette with skeleton '\(skeletonPath)' at time \(animTime)")
                }
            } else if model.skeletons.count == 1, let onlySkeleton = model.skeletons.values.first {
                // Fallback: if only one skeleton exists, use it
                mesh.skin?.updatePalette(skeleton: onlySkeleton)
                if debugLogging {
                    print("[AnimationLayerSystem] Updated ONLY mesh skin palette at time \(animTime)")
                }
            }
        }
    }

    // MARK: - Convenience Methods

    /// Force update all poses regardless of dirty state
    /// Useful for initialization or when scrubbing animations
    func forceUpdateAllPoses() {
        guard let model = model else { return }

        if debugLogging {
            print("[AnimationLayerSystem] Force updating all poses")
        }

//        for id in evaluationOrder {
//            if let layer = layers[id] {
//                updatePoses(for: layer, model: model)
//            }
//        }
        
        for id in layerSetEvaluationOrder {
            if let layerSet = layerSets[id] {
                for layer in layerSet.layers {
                    updatePoses(for: layer, model: model)
                }
            }
        }
    }

    /// Reset all layers to their default state
    func resetAlllayers() {
//        for layer in layers.values {
//            if let binary = layer as? BinaryAnimationLayer {
//                binary.setInactiveImmediate()
//            } else if let continuous = layer as? ContinuousAnimationLayer {
//                continuous.setValueImmediate(continuous.range.min)
//            }
//        }
        
        for layerSet in layerSets.values {
            for layer in layerSet.layers {
                if let binary = layer as? BinaryAnimationLayer {
                    binary.setInactiveImmediate()
                } else if let continuous = layer as? ContinuousAnimationLayer {
                    continuous.setValueImmediate(continuous.range.min)
                }
            }
        }
        
        forceUpdateAllPoses()

        if debugLogging {
            print("[AnimationLayerSystem] Reset all layers to default state")
        }
    }

    /// Set a specific layer to a normalized progress/value
    /// - Parameters:
    ///   - layerID: The layer ID
    ///   - normalizedValue: Value from 0.0 to 1.0
    func setlayerValue(_ layerID: String, normalizedValue: Float) {
        guard let layer = layers[layerID] else {
            print("[AnimationLayerSystem] Warning: layer '\(layerID)' not found")
            return
        }

        if let binary = layer as? BinaryAnimationLayer {
            binary.setProgress(normalizedValue)
        } else if let continuous = layer as? ContinuousAnimationLayer {
            continuous.setNormalizedValue(normalizedValue)
        }
    }
}

// MARK: - Debug Helpers

extension AnimationLayerSystem {
    /// Print current state of all layers
    func debugPrintState() {
        print("[AnimationLayerSystem] State:")
        print("  Model: \(model?.name ?? "nil")")
        print("  layers (\(layers.count)):")

        for id in evaluationOrder {
            if let layer = layers[id] {
                print("    - \(id): dirty=\(layer.isDirty), time=\(layer.getAnimationTime())")
                if let binary = layer as? BinaryAnimationLayer {
                    print("      state=\(binary.state), progress=\(binary.progress)")
                } else if let continuous = layer as? ContinuousAnimationLayer {
                    print("      value=\(continuous.value), target=\(continuous.targetValue)")
                }
            }
        }
    }

    /// Print mask coverage information for debugging
    func debugPrintMaskCoverage() {
        guard let model = model else {
            print("[AnimationLayerSystem] No model available")
            return
        }

        print("[AnimationLayerSystem] Mask Coverage Analysis:")

        for id in evaluationOrder {
            guard let layer = layers[id] else { continue }
            let mask = layer.mask

            print("  layer '\(id)':")
            print("    Joint paths in mask: \(mask.jointPaths.count)")
            print("    Mesh indices in mask: \(mask.meshIndices.count)")

            // Check which skeletons have matching joints
            for (skeletonPath, skeleton) in model.skeletons {
                let matchingJoints = skeleton.jointPaths.filter { mask.contains(jointPath: $0) }
                if !matchingJoints.isEmpty {
                    print("    Skeleton '\(skeletonPath)': \(matchingJoints.count)/\(skeleton.jointPaths.count) joints matched")
                }
            }
        }
    }
}
