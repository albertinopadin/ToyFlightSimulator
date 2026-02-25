//
//  AnimationLayerSystem.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/13/26.
//

import Foundation

/// Pre-computed mapping from a channel to the skeletons and meshes it affects.
/// Built once at registration time so the per-frame update path does zero discovery work.
struct ChannelMapping {
    /// Skeleton paths affected by this channel, paired with the clip to use
    let skeletonEntries: [(path: String, clip: AnimationClip)]

    /// Mesh indices that need transform and/or skin updates
    let affectedMeshIndices: [Int]

    /// For each affected mesh index, the skeleton (if any) that drives its skin
    let meshSkeletonLookup: [Int: Skeleton]
}

/// Manages multiple animation layers and coordinates pose updates.
/// Each layer groups related animation channels, and the layer system
/// ensures only dirty channels trigger pose recalculations.
///
/// Performance design:
/// - Layers stored in an array for zero-overhead frame iteration (no dictionary lookups)
/// - Skeleton/mesh affinity pre-computed at registration time via `ChannelMapping`
/// - Single-skeleton fallback cached once at init
/// - Single merged loop in `update()` for state + dirty pose updates
final class AnimationLayerSystem {
    // MARK: - Properties

    /// Reference to the model containing animation data (skeletons, clips, skins)
    private weak var model: UsdModel?

    /// Registered animation channels, keyed by their unique ID (for name-based lookups only)
    private var channelsByID: [String: AnimationChannel] = [:]

    /// Ordered layers for deterministic frame iteration (no dictionary lookups per frame)
    private var orderedLayers: [AnimationLayer] = []

    /// Layer lookup by ID (for name-based access only, not used in hot path)
    private var layersByID: [String: Int] = [:]

    /// Pre-computed channel-to-skeleton/mesh mappings, keyed by channel ID
    private var channelMappings: [String: ChannelMapping] = [:]

    /// Cached single skeleton when model has exactly one (avoids repeated dictionary access)
    private var singleSkeleton: Skeleton?
    
    private let debugLogging: Bool = false

    // MARK: - Computed Properties

    /// All registered channel IDs
    var channelIDs: [String] {
        Array(channelsByID.keys)
    }

    /// Number of registered channels
    var channelCount: Int {
        channelsByID.count
    }

    // MARK: - Initialization

    /// Creates a new animation layer system for a model
    /// - Parameter model: The UsdModel containing skeletons, animation clips, and skins
    init(model: UsdModel) {
        self.model = model
        model.hasExternalAnimator = true

        // Cache single-skeleton fallback
        if model.skeletons.count == 1 {
            singleSkeleton = model.skeletons.values.first
        }
        
        if debugLogging {
            print("[AnimationLayerSystem] Initialized for model: \(model.name)")
            print("[AnimationLayerSystem] \(model.skeletons.count) Available skeletons: \(model.skeletons.keys)")
            print("[AnimationLayerSystem] \(model.animationClips.count) Available clips: \(model.animationClips.keys)")
        }
    }

    // MARK: - Channel Management

    /// Register a new animation channel
    /// - Parameter channel: The channel to register
    func registerChannel(_ channel: AnimationChannel) {
        let id = channel.id

        if channelsByID[id] != nil {
            print("[AnimationLayerSystem] Warning: Replacing existing channel '\(id)'")
        }

        channelsByID[id] = channel

        // If channel doesn't have an animation clip assigned, try to find a matching one
        // BUG ???
        if channel.animationClip == nil, let model = model {
            if let firstClip = model.animationClips.values.first {
                channel.animationClip = firstClip
            }
        }

        // Build pre-computed mapping for this channel
        if let model = model {
            channelMappings[id] = buildMapping(for: channel, model: model)
        }
        
        if debugLogging {
            print("[AnimationLayerSystem] Registered channel '\(id)' with mask: \(channel.mask)")
        }
    }

    /// Unregister a channel by its ID
    /// - Parameter id: The channel ID to remove
    func unregisterChannel(_ id: String) {
        channelsByID.removeValue(forKey: id)
        channelMappings.removeValue(forKey: id)
        
        if debugLogging {
            print("[AnimationLayerSystem] Unregistered channel '\(id)'")
        }
    }

    /// Get a channel by its ID
    /// - Parameter id: The channel ID
    /// - Returns: The channel if found, nil otherwise
    func channel(_ id: String) -> AnimationChannel? {
        channelsByID[id]
    }

    /// Get a typed channel by its ID
    /// - Parameters:
    ///   - id: The channel ID
    ///   - type: The expected channel type
    /// - Returns: The channel cast to the specified type, or nil if not found or wrong type
    func channel<T: AnimationChannel>(_ id: String, as type: T.Type) -> T? {
        channelsByID[id] as? T
    }

    /// Check if a channel with the given ID exists
    /// - Parameter id: The channel ID to check
    /// - Returns: True if the channel exists
    func hasChannel(_ id: String) -> Bool {
        channelsByID[id] != nil
    }

    // MARK: - Layer Management

    /// Register a new animation layer (group of channels)
    /// - Parameter layer: The layer to register
    func registerLayer(_ layer: AnimationLayer) {
        let id = layer.id

        if let existingIndex = layersByID[id] {
            print("[AnimationLayerSystem] Warning: Replacing existing layer '\(id)'")
            orderedLayers.remove(at: existingIndex)
            // Rebuild index map after removal
            rebuildLayerIndex()
        }

        layersByID[id] = orderedLayers.count
        orderedLayers.append(layer)

        // Register all channels in this layer
        for channel in layer.channels {
            registerChannel(channel)
        }
        
        if debugLogging {
            print("[AnimationLayerSystem] Registered layer '\(id)'")
        }
    }

    /// Get a layer by its ID
    /// - Parameter id: The layer ID
    /// - Returns: The layer if found, nil otherwise
    func layer(_ id: String) -> AnimationLayer? {
        guard let index = layersByID[id] else { return nil }
        return orderedLayers[index]
    }

    /// Check if a layer with the given ID exists
    /// - Parameter id: The layer ID to check
    /// - Returns: True if the layer exists
    func hasLayer(_ id: String) -> Bool {
        layersByID[id] != nil
    }

    // MARK: - Update (Hot Path)

    /// Update all layers and refresh poses for any channels that changed.
    /// Single merged loop: updates layer state machines then immediately processes dirty channels.
    /// - Parameter deltaTime: Time since last update in seconds
    func update(deltaTime: Float) {
        guard let model = model else { return }

        for layer in orderedLayers {
            layer.update(deltaTime: deltaTime)

            for channel in layer.channels {
                guard channel.isDirty else { continue }
                updatePoses(for: channel, model: model)
                channel.clearDirty()
            }
        }
    }

    // MARK: - Pose Updates (Hot Path)

    /// Update skeleton and mesh poses for a single channel using pre-computed mappings.
    /// - Parameters:
    ///   - channel: The channel to update poses for
    ///   - model: The model containing animation data
    private func updatePoses(for channel: AnimationChannel, model: UsdModel) {
        let animTime = channel.getAnimationTime()
        
        if channel.id.starts(with: "flaperon") {
            print("Updating pose for flaperon, animTime: \(animTime)")
        }
        
        if debugLogging {
            print("[AnimationLayerSystem] Channel '\(channel.id)' animation time: \(animTime)")
        }

        guard let mapping = channelMappings[channel.id] else {
            // Fallback for channels registered without a mapping (shouldn't happen)
            print("Calling updatePosesFallback for unmapped channel")
            updatePosesFallback(for: channel, model: model, animTime: animTime)
            return
        }

        // Update affected skeletons
        for entry in mapping.skeletonEntries {
            if channel.id.starts(with: "flaperon") {
                print("Updating pose for skeleton at path: \(entry.path) with clip: \(entry.clip.name)")
            }
            model.skeletons[entry.path]?.updatePose(at: animTime, animationClip: entry.clip)
        }

        // Update affected meshes (transforms and skins)
        for meshIndex in mapping.affectedMeshIndices {
            let mesh = model.meshes[meshIndex]

            // Update transform component if present (for non-skeletal mesh animation)
            mesh.transform?.setCurrentTransform(at: animTime)

            // Update skin with skeleton pose
            if let skeleton = mapping.meshSkeletonLookup[meshIndex] {
                mesh.skin?.updatePalette(skeleton: skeleton)
            } else if let fallback = singleSkeleton {
                mesh.skin?.updatePalette(skeleton: fallback)
            }
        }
    }

    /// Fallback pose update that discovers affected skeletons/meshes at runtime.
    /// Only used if a channel somehow has no pre-computed mapping.
    private func updatePosesFallback(for channel: AnimationChannel, model: UsdModel, animTime: Float) {
        print("[updatePosesFallback] AnimationLayerSystem: Falling back to generic channel pose update.")
        
        let mask = channel.mask
        var affectedSkeletonPaths: Set<String> = []

        for (skeletonPath, skeleton) in model.skeletons {
            let hasAffectedJoints = skeleton.jointPaths.contains { mask.contains(jointPath: $0) }

            if hasAffectedJoints || mask.jointPaths.isEmpty {
                affectedSkeletonPaths.insert(skeletonPath)

                let clip = channel.animationClip
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

        for (index, mesh) in model.meshes.enumerated() {
            let meshDirectlyAffected = mask.contains(meshIndex: index)
            var meshSkeletonAffected = false
            if let skeletonPath = model.meshSkeletonMap[index] {
                meshSkeletonAffected = affectedSkeletonPaths.contains(skeletonPath)
            }

            guard meshDirectlyAffected || meshSkeletonAffected || mask.isEmpty || mesh.transform != nil else {
                continue
            }

            mesh.transform?.setCurrentTransform(at: animTime)

            if let skeletonPath = model.meshSkeletonMap[index],
               let skeleton = model.skeletons[skeletonPath] {
                mesh.skin?.updatePalette(skeleton: skeleton)
                if debugLogging {
                    print("[AnimationLayerSystem] Updated mesh skin palette with skeleton '\(skeletonPath)' at time \(animTime)")
                }
            } else if let fallback = singleSkeleton {
                mesh.skin?.updatePalette(skeleton: fallback)
                if debugLogging {
                    print("[AnimationLayerSystem] Updated ONLY mesh skin palette at time \(animTime)")
                }
            }
        }
    }

    // MARK: - Mapping Construction (Registration Time Only)

    /// Build a pre-computed mapping for a channel based on its mask and the model's topology.
    /// Called once at registration time, never during the frame loop.
    private func buildMapping(for channel: AnimationChannel, model: UsdModel) -> ChannelMapping {
        let mask = channel.mask

        // Determine affected skeletons and their clips
        var skeletonEntries: [(path: String, clip: AnimationClip)] = []
        var affectedSkeletonPaths: Set<String> = []

        for (skeletonPath, skeleton) in model.skeletons {
            let hasAffectedJoints = skeleton.jointPaths.contains { mask.contains(jointPath: $0) }

            if hasAffectedJoints || mask.jointPaths.isEmpty {
                affectedSkeletonPaths.insert(skeletonPath)

                let clip = channel.animationClip
                    ?? model.animationClips[model.skeletonAnimationMap[skeletonPath] ?? ""]
                    ?? model.animationClips.values.first

                if let clip = clip {
                    skeletonEntries.append((path: skeletonPath, clip: clip))
                }
            }
        }

        // Determine affected mesh indices and build per-mesh skeleton lookup
        var affectedMeshIndices: [Int] = []
        var meshSkeletonLookup: [Int: Skeleton] = [:]

        for (index, mesh) in model.meshes.enumerated() {
            let meshDirectlyAffected = mask.contains(meshIndex: index)

            var meshSkeletonAffected = false
            if let skeletonPath = model.meshSkeletonMap[index] {
                meshSkeletonAffected = affectedSkeletonPaths.contains(skeletonPath)
            }

            guard meshDirectlyAffected || meshSkeletonAffected || mask.isEmpty || mesh.transform != nil else {
                continue
            }

            affectedMeshIndices.append(index)

            // Pre-resolve the skeleton for this mesh's skin
            if let skeletonPath = model.meshSkeletonMap[index],
               let skeleton = model.skeletons[skeletonPath] {
                meshSkeletonLookup[index] = skeleton
            }
            // Note: singleSkeleton fallback is handled at update time via the cached property
        }

        return ChannelMapping(
            skeletonEntries: skeletonEntries,
            affectedMeshIndices: affectedMeshIndices,
            meshSkeletonLookup: meshSkeletonLookup
        )
    }

    // MARK: - Convenience Methods

    /// Force update all poses regardless of dirty state.
    /// Useful for initialization or when scrubbing animations.
    func forceUpdateAllPoses() {
        guard let model = model else { return }
        
        if debugLogging {
            print("[AnimationLayerSystem] Force updating all poses")
        }

        for layer in orderedLayers {
            for channel in layer.channels {
                updatePoses(for: channel, model: model)
            }
        }
    }

    /// Reset all channels to their default state
    func resetAllChannels() {
        for layer in orderedLayers {
            for channel in layer.channels {
                if let binary = channel as? BinaryAnimationChannel {
                    binary.setInactiveImmediate()
                } else if let continuous = channel as? ContinuousAnimationChannel {
                    continuous.setValueImmediate(continuous.range.min)
                }
            }
        }
        
        if debugLogging {
            print("[AnimationLayerSystem] Reset all channels to default state")
        }

        forceUpdateAllPoses()
    }

    /// Set a specific channel to a normalized progress/value
    /// - Parameters:
    ///   - channelID: The channel ID
    ///   - normalizedValue: Value from 0.0 to 1.0
    func setChannelValue(_ channelID: String, normalizedValue: Float) {
        guard let channel = channelsByID[channelID] else {
            print("[AnimationLayerSystem] Warning: Channel '\(channelID)' not found")
            return
        }

        if let binary = channel as? BinaryAnimationChannel {
            binary.setProgress(normalizedValue)
        } else if let continuous = channel as? ContinuousAnimationChannel {
            continuous.setNormalizedValue(normalizedValue)
        }
    }

    // MARK: - Private Helpers

    /// Rebuild the layersByID index map after a removal
    private func rebuildLayerIndex() {
        layersByID.removeAll(keepingCapacity: true)
        for (index, layer) in orderedLayers.enumerated() {
            layersByID[layer.id] = index
        }
    }
}

// MARK: - Debug Helpers

extension AnimationLayerSystem {
    /// Print current state of all channels
    func debugPrintState() {
        print("[AnimationLayerSystem] State:")
        print("  Model: \(model?.name ?? "nil")")
        print("  Layers: \(orderedLayers.count), Channels: \(channelsByID.count)")

        for layer in orderedLayers {
            print("  Layer '\(layer.id)' (\(layer.channels.count) channels):")
            for channel in layer.channels {
                print("    - \(channel.id): dirty=\(channel.isDirty), time=\(channel.getAnimationTime())")
                if let binary = channel as? BinaryAnimationChannel {
                    print("      state=\(binary.state), progress=\(binary.progress)")
                } else if let continuous = channel as? ContinuousAnimationChannel {
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

        for layer in orderedLayers {
            for channel in layer.channels {
                let mask = channel.mask

                print("  Channel '\(channel.id)':")
                print("    Joint paths in mask: \(mask.jointPaths.count)")
                print("    Mesh indices in mask: \(mask.meshIndices.count)")

                if let mapping = channelMappings[channel.id] {
                    print("    Pre-computed: \(mapping.skeletonEntries.count) skeletons, \(mapping.affectedMeshIndices.count) meshes")
                }

                for (skeletonPath, skeleton) in model.skeletons {
                    let matchingJoints = skeleton.jointPaths.filter { mask.contains(jointPath: $0) }
                    if !matchingJoints.isEmpty {
                        print("    Skeleton '\(skeletonPath)': \(matchingJoints.count)/\(skeleton.jointPaths.count) joints matched")
                    }
                }
            }
        }
    }
}
