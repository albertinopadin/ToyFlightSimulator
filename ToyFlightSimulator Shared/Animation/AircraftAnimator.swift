//
//  AircraftAnimator.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/10/26.
//

import Foundation

/// Represents the state of the landing gear
enum GearState {
    case up          // Gear fully retracted
    case extending   // Gear in the process of extending
    case down        // Gear fully extended
    case retracting  // Gear in the process of retracting
}

/// Aircraft-specific animation controller that manages landing gear and other aircraft animations.
/// This class serves as the high-level animation interface for aircraft, handling state machines
/// for gear, flaps, etc., while delegating low-level skeleton/skin updates to the UsdModel's data.
final class AircraftAnimator: AnimationController {
    // MARK: - Properties

    /// Reference to the UsdModel containing animation data (skeletons, clips, skins)
    private weak var model: UsdModel?

    /// Current playback state
    private(set) var playbackState: AnimationPlaybackState = .stopped

    /// Current animation time in seconds
    private(set) var currentTime: Float = 0

    /// Total duration of the current animation
    private(set) var duration: Float = 0

    /// Playback speed multiplier
    private var playbackSpeed: Float = 1.0

    /// Whether the animation should loop
    private var shouldLoop: Bool = false

    /// Name of the currently playing animation clip
    private var currentClipName: String?

    // MARK: - Gear State Machine

    /// Current state of the landing gear
    private(set) var gearState: GearState = .down

    /// Animation progress for the landing gear (0.0 = fully up, 1.0 = fully down)
    private(set) var gearAnimationProgress: Float = 1.0

    /// Duration for gear extension/retraction animation in seconds
    var gearAnimationDuration: Float = 3.0

    // MARK: - Initialization

    /// Creates an aircraft animator with a reference to the model's animation data
    /// - Parameter model: The UsdModel containing skeletons, animation clips, and skins
    init(model: UsdModel) {
        self.model = model

        // Determine the animation duration from the model's animation clips
        if let firstClip = model.animationClips.values.first {
            self.duration = firstClip.duration
            self.gearAnimationDuration = firstClip.duration
        }

        // Start with gear down (animation at end position)
        self.gearAnimationProgress = 1.0
        self.currentTime = duration
        updateSkeletonPoses()
    }

    // MARK: - AnimationController Protocol

    func play(clipName: String, speed: Float = 1.0, loop: Bool = false) {
        currentClipName = clipName
        playbackSpeed = speed
        shouldLoop = loop
        playbackState = .playing
    }

    func pause() {
        playbackState = .paused
    }

    func stop() {
        playbackState = .stopped
        currentTime = 0
        gearAnimationProgress = playbackSpeed >= 0 ? 0 : 1.0
    }

    func setNormalizedTime(_ t: Float) {
        let clampedT = max(0, min(1, t))
        currentTime = clampedT * duration
        gearAnimationProgress = clampedT
        updateSkeletonPoses()
    }

    func update(deltaTime: Float) {
        updateGearStateMachine(deltaTime: deltaTime)
    }

    // MARK: - Gear Control API

    /// Initiates landing gear extension
    /// Only works when gear is fully up
    func extendGear() {
        guard gearState == .up else {
            print("[AircraftAnimator] Cannot extend gear - current state: \(gearState)")
            return
        }
        print("[AircraftAnimator] Beginning gear extension")
        gearState = .extending
        playbackState = .playing
    }

    /// Initiates landing gear retraction
    /// Only works when gear is fully down
    func retractGear() {
        guard gearState == .down else {
            print("[AircraftAnimator] Cannot retract gear - current state: \(gearState)")
            return
        }
        print("[AircraftAnimator] Beginning gear retraction")
        gearState = .retracting
        playbackState = .playing
    }

    /// Toggles landing gear between extended and retracted states
    func toggleGear() {
        switch gearState {
        case .up:
            extendGear()
        case .down:
            retractGear()
        case .extending, .retracting:
            print("[AircraftAnimator] Gear animation in progress, ignoring toggle")
        }
    }

    /// Returns true if the gear is fully down
    var isGearDown: Bool {
        return gearState == .down
    }

    /// Returns true if the gear is fully up
    var isGearUp: Bool {
        return gearState == .up
    }

    /// Returns true if a gear animation is in progress
    var isGearAnimating: Bool {
        return gearState == .extending || gearState == .retracting
    }

    // MARK: - Private Methods

    /// Updates the gear state machine based on elapsed time
    private func updateGearStateMachine(deltaTime: Float) {
        switch gearState {
        case .extending:
            // Animate from 0 (up) to 1 (down)
            gearAnimationProgress += deltaTime / gearAnimationDuration
            if gearAnimationProgress >= 1.0 {
                gearAnimationProgress = 1.0
                gearState = .down
                playbackState = .stopped
                print("[AircraftAnimator] Gear extension complete")
            }
            updateSkeletonPoses()

        case .retracting:
            // Animate from 1 (down) to 0 (up)
            gearAnimationProgress -= deltaTime / gearAnimationDuration
            if gearAnimationProgress <= 0.0 {
                gearAnimationProgress = 0.0
                gearState = .up
                playbackState = .stopped
                print("[AircraftAnimator] Gear retraction complete")
            }
            updateSkeletonPoses()

        case .up, .down:
            // No animation in progress
            break
        }
    }

    /// Updates all skeleton poses and mesh skins based on current animation progress
    private func updateSkeletonPoses() {
        guard let model = model else { return }

        // Calculate animation time from progress
        let animationTime = gearAnimationProgress * duration

        // Update each skeleton with its associated animation clip
        for (skeletonPath, skeleton) in model.skeletons {
            // Find the animation clip associated with this skeleton
            if let clipName = model.skeletonAnimationMap[skeletonPath],
               let clip = model.animationClips[clipName] {
                skeleton.updatePose(at: animationTime, animationClip: clip)
            } else if let firstClip = model.animationClips.values.first {
                // Fallback: use first available clip
                skeleton.updatePose(at: animationTime, animationClip: firstClip)
            }
        }

        // Update mesh transforms and skins
        for (index, mesh) in model.meshes.enumerated() {
            // Update TransformComponent if present (non-skeletal mesh animation)
            if mesh.transform != nil {
                mesh.transform?.setCurrentTransform(at: animationTime)
            }

            // Update skin with the correct skeleton for this mesh
            if let skeletonPath = model.meshSkeletonMap[index],
               let skeleton = model.skeletons[skeletonPath] {
                mesh.skin?.updatePalette(skeleton: skeleton)
            } else if model.skeletons.count == 1,
                      let onlySkeleton = model.skeletons.values.first {
                // Fallback: if only one skeleton exists, use it
                mesh.skin?.updatePalette(skeleton: onlySkeleton)
            }
        }
    }

    // MARK: - Debug

    /// Prints current animator state for debugging
    func debugPrintState() {
        print("""
        [AircraftAnimator State]
          Gear State: \(gearState)
          Gear Progress: \(String(format: "%.2f", gearAnimationProgress))
          Animation Time: \(String(format: "%.2f", currentTime)) / \(String(format: "%.2f", duration))
          Playback State: \(playbackState)
        """)
    }
}
