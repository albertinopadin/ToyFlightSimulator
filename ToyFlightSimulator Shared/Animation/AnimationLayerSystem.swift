//
//  AnimationLayerSystem.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/13/26.
//

import Foundation

/// Manages multiple animation channels and coordinates pose updates.
/// Each channel controls a specific animatable subsystem (landing gear, flaps, etc.)
/// and the layer system ensures only dirty channels trigger pose recalculations.
final class AnimationLayerSystem {
    // MARK: - Properties

    /// Reference to the model containing animation data (skeletons, clips, skins)
    private weak var model: UsdModel?

    /// Registered animation channels, keyed by their unique ID
    private var channels: [String: AnimationChannel] = [:]

    /// Order in which channels are evaluated (for deterministic updates)
    private var evaluationOrder: [String] = []

    /// Whether debug logging is enabled
    var debugLogging: Bool = false

    // MARK: - Computed Properties

    /// All registered channel IDs
    var channelIDs: [String] {
        Array(channels.keys)
    }

    /// Number of registered channels
    var channelCount: Int {
        channels.count
    }

    /// Whether any channel is currently dirty (needs pose update)
    var hasDirtyChannels: Bool {
        channels.values.contains { $0.isDirty }
    }

    // MARK: - Initialization

    /// Creates a new animation layer system for a model
    /// - Parameter model: The UsdModel containing skeletons, animation clips, and skins
    init(model: UsdModel) {
        self.model = model
        model.hasExternalAnimator = true

        if debugLogging {
            print("[AnimationLayerSystem] Initialized for model: \(model.name)")
            print("[AnimationLayerSystem] Available skeletons: \(model.skeletons.keys)")
            print("[AnimationLayerSystem] Available clips: \(model.animationClips.keys)")
        }
    }

    // MARK: - Channel Management

    /// Register a new animation channel
    /// - Parameter channel: The channel to register
    func registerChannel(_ channel: AnimationChannel) {
        let id = channel.id

        if channels[id] != nil {
            print("[AnimationLayerSystem] Warning: Replacing existing channel '\(id)'")
            evaluationOrder.removeAll { $0 == id }
        }

        channels[id] = channel
        evaluationOrder.append(id)

        // If channel doesn't have an animation clip assigned, try to find a matching one
        if channel.animationClip == nil, let model = model {
            // Try to find a clip that might match this channel
            if let firstClip = model.animationClips.values.first {
                channel.animationClip = firstClip
            }
        }

        if debugLogging {
            print("[AnimationLayerSystem] Registered channel '\(id)' with mask: \(channel.mask)")
        }
    }

    /// Unregister a channel by its ID
    /// - Parameter id: The channel ID to remove
    func unregisterChannel(_ id: String) {
        channels.removeValue(forKey: id)
        evaluationOrder.removeAll { $0 == id }

        if debugLogging {
            print("[AnimationLayerSystem] Unregistered channel '\(id)'")
        }
    }

    /// Get a channel by its ID
    /// - Parameter id: The channel ID
    /// - Returns: The channel if found, nil otherwise
    func channel(_ id: String) -> AnimationChannel? {
        channels[id]
    }

    /// Get a typed channel by its ID
    /// - Parameters:
    ///   - id: The channel ID
    ///   - type: The expected channel type
    /// - Returns: The channel cast to the specified type, or nil if not found or wrong type
    func channel<T: AnimationChannel>(_ id: String, as type: T.Type) -> T? {
        channels[id] as? T
    }

    /// Check if a channel with the given ID exists
    /// - Parameter id: The channel ID to check
    /// - Returns: True if the channel exists
    func hasChannel(_ id: String) -> Bool {
        channels[id] != nil
    }

    // MARK: - Update

    /// Update all channels and refresh poses for any that changed
    /// - Parameter deltaTime: Time since last update in seconds
    func update(deltaTime: Float) {
        guard let model = model else { return }

        // Update all channel state machines
        for id in evaluationOrder {
            channels[id]?.update(deltaTime: deltaTime)
        }

        // Update poses for dirty channels
        for id in evaluationOrder {
            guard let channel = channels[id], channel.isDirty else { continue }

            if debugLogging {
                print("[AnimationLayerSystem] Updating poses for dirty channel '\(id)'")
            }

            updatePoses(for: channel, model: model)
            channel.clearDirty()
        }
    }

    // MARK: - Pose Updates

    /// Update skeleton and mesh poses for a single channel
    /// - Parameters:
    ///   - channel: The channel to update poses for
    ///   - model: The model containing animation data
    private func updatePoses(for channel: AnimationChannel, model: UsdModel) {
        let animTime = channel.getAnimationTime()
        let mask = channel.mask

        if debugLogging {
            print("[AnimationLayerSystem] Channel '\(channel.id)' animation time: \(animTime)")
        }

        // Determine which skeletons are affected by this channel's mask
        var affectedSkeletonPaths: Set<String> = []

        for (skeletonPath, skeleton) in model.skeletons {
            // Check if any joints in this skeleton are in the channel mask
            let hasAffectedJoints = skeleton.jointPaths.contains { mask.contains(jointPath: $0) }

            if hasAffectedJoints || mask.jointPaths.isEmpty {
                // If mask has no joints specified, it affects all (for backward compatibility)
                affectedSkeletonPaths.insert(skeletonPath)

                // Find the animation clip to use
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

        // Update mesh transforms and skins for affected meshes
        for (index, mesh) in model.meshes.enumerated() {
            // Check if this mesh is directly affected by the mask
            let meshDirectlyAffected = mask.contains(meshIndex: index)

            // Check if this mesh's skeleton is affected
            var meshSkeletonAffected = false
            if let skeletonPath = model.meshSkeletonMap[index] {
                meshSkeletonAffected = affectedSkeletonPaths.contains(skeletonPath)
            }

            // Skip if this mesh is not affected
            guard meshDirectlyAffected || meshSkeletonAffected || mask.isEmpty else { continue }

            // Update transform component if present (for non-skeletal mesh animation)
            if mesh.transform != nil {
                mesh.transform?.setCurrentTransform(at: animTime)
            }

            // Update skin with skeleton pose
            if let skeletonPath = model.meshSkeletonMap[index],
               let skeleton = model.skeletons[skeletonPath] {
                mesh.skin?.updatePalette(skeleton: skeleton)
            } else if model.skeletons.count == 1, let onlySkeleton = model.skeletons.values.first {
                // Fallback: if only one skeleton exists, use it
                mesh.skin?.updatePalette(skeleton: onlySkeleton)
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

        for id in evaluationOrder {
            if let channel = channels[id] {
                updatePoses(for: channel, model: model)
            }
        }
    }

    /// Reset all channels to their default state
    func resetAllChannels() {
        for channel in channels.values {
            if let binary = channel as? BinaryAnimationChannel {
                binary.setInactiveImmediate()
            } else if let continuous = channel as? ContinuousAnimationChannel {
                continuous.setValueImmediate(continuous.range.min)
            }
        }
        forceUpdateAllPoses()

        if debugLogging {
            print("[AnimationLayerSystem] Reset all channels to default state")
        }
    }

    /// Set a specific channel to a normalized progress/value
    /// - Parameters:
    ///   - channelID: The channel ID
    ///   - normalizedValue: Value from 0.0 to 1.0
    func setChannelValue(_ channelID: String, normalizedValue: Float) {
        guard let channel = channels[channelID] else {
            print("[AnimationLayerSystem] Warning: Channel '\(channelID)' not found")
            return
        }

        if let binary = channel as? BinaryAnimationChannel {
            binary.setProgress(normalizedValue)
        } else if let continuous = channel as? ContinuousAnimationChannel {
            continuous.setNormalizedValue(normalizedValue)
        }
    }
}

// MARK: - Debug Helpers

extension AnimationLayerSystem {
    /// Print current state of all channels
    func debugPrintState() {
        print("[AnimationLayerSystem] State:")
        print("  Model: \(model?.name ?? "nil")")
        print("  Channels (\(channels.count)):")

        for id in evaluationOrder {
            if let channel = channels[id] {
                print("    - \(id): dirty=\(channel.isDirty), time=\(channel.getAnimationTime())")
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

        for id in evaluationOrder {
            guard let channel = channels[id] else { continue }
            let mask = channel.mask

            print("  Channel '\(id)':")
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
