//
//  AircraftAnimator.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/10/26.
//

import Foundation

/// Represents the state of the landing gear (legacy compatibility)
enum GearState {
    case up          // Gear fully retracted
    case extending   // Gear in the process of extending
    case down        // Gear fully extended
    case retracting  // Gear in the process of retracting
}

/// Aircraft-specific animation controller that manages landing gear and other aircraft animations.
/// This class serves as the high-level animation interface for aircraft, using AnimationLayerSystem
/// internally to manage multiple independent animation layers (groups of channels).
class AircraftAnimator: AnimationController {
    // MARK: - Properties

    /// Reference to the UsdModel containing animation data (skeletons, clips, skins)
    internal weak var model: UsdModel?

    /// Internal layer system that manages animation layers and channels
    internal var layerSystem: AnimationLayerSystem?

    /// Current playback state (legacy compatibility)
    private(set) var playbackState: AnimationPlaybackState = .stopped

    /// Current animation time in seconds (legacy compatibility)
    private(set) var currentTime: Float = 0

    /// Playback speed multiplier (legacy compatibility)
    private var playbackSpeed: Float = 1.0

    /// Whether the animation should loop (legacy compatibility)
    private var shouldLoop: Bool = false

    /// Name of the currently playing animation clip (legacy compatibility)
    private var currentClipName: String?

    // MARK: - Landing Gear Layer Access

    /// The landing gear layer ID (standard across all aircraft)
    static let landingGearLayerID = "landingGear"

    /// Direct access to the landing gear layer
    var landingGearLayer: AnimationLayer? {
        layerSystem?.layer(Self.landingGearLayerID)
    }

    // MARK: - Gear State (Legacy Compatibility)

    /// Current state of the landing gear (maps to layer state)
    var gearState: GearState {
        guard let layer = landingGearLayer else { return .down }
        switch layer.state {
            case .inactive: return .up
            case .activating: return .extending
            case .active: return .down
            case .deactivating: return .retracting
        }
    }

    /// Animation progress for the landing gear (0.0 = fully up, 1.0 = fully down)
    var gearAnimationProgress: Float {
        landingGearLayer?.progress ?? 1.0
    }

    /// Duration for gear extension/retraction animation in seconds
    var gearAnimationDuration: Float {
        landingGearLayer?.transitionDuration ?? 0
    }

    // MARK: - Initialization

    /// Creates an aircraft animator with a reference to the model's animation data
    /// - Parameter model: The UsdModel containing skeletons, animation clips, and skins
    init(model: UsdModel) {
        self.model = model

        // Create the layer system
        self.layerSystem = AnimationLayerSystem(model: model)

        print("[AircraftAnimator init] model: \(model.name)")
        for (key, clip) in model.animationClips {
            print("[AircraftAnimator init] Clip key: \(key), name: \(clip.name), duration: \(clip.duration)s")
        }
    }

    /// Subclasses should call this to register their layers after init
    func setupLayers() {
        // Base implementation does nothing
        // Subclasses override to register aircraft-specific layers
    }

    // MARK: - Layer Management

    /// Register an animation channel
    /// - Parameter channel: The channel to register
    func registerChannel(_ channel: AnimationChannel) {
        layerSystem?.registerChannel(channel)
    }

    /// Register an animation layer (group of channels)
    /// - Parameter layer: The layer to register
    func registerLayer(_ layer: AnimationLayer) {
        layerSystem?.registerLayer(layer)
    }

    /// Get a channel by ID
    /// - Parameter id: The channel ID
    /// - Returns: The channel if found
    func channel(_ id: String) -> AnimationChannel? {
        layerSystem?.channel(id)
    }

    /// Get a typed channel by ID
    /// - Parameters:
    ///   - id: The channel ID
    ///   - type: The expected channel type
    /// - Returns: The channel cast to the specified type
    func channel<T: AnimationChannel>(_ id: String, as type: T.Type) -> T? {
        layerSystem?.channel(id, as: type)
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
    }

    func update(deltaTime: Float) {
        // Delegate to the layer system
        layerSystem?.update(deltaTime: deltaTime)
    }

    // MARK: - Gear Control API (Legacy Compatibility)

    /// Initiates landing gear extension
    /// Only works when gear is fully up
    func extendGear() {
        guard let layer = landingGearLayer else {
            print("[AircraftAnimator] No landing gear layer registered")
            return
        }
        layer.activate()
        playbackState = layer.isAnimating ? .playing : .stopped
    }

    /// Initiates landing gear retraction
    /// Only works when gear is fully down
    func retractGear() {
        guard let layer = landingGearLayer else {
            print("[AircraftAnimator] No landing gear layer registered")
            return
        }
        layer.deactivate()
        playbackState = layer.isAnimating ? .playing : .stopped
    }

    /// Toggles landing gear between extended and retracted states
    func toggleGear() {
        guard let layer = landingGearLayer else {
            print("[AircraftAnimator] No landing gear layer registered")
            return
        }
        layer.toggle()
        print("[AircraftAnimator] Toggled Landing Gear")
        playbackState = layer.isAnimating ? .playing : .stopped
    }

    /// Returns true if the gear is fully down
    var isGearDown: Bool {
        landingGearLayer?.isActive ?? true
    }

    /// Returns true if the gear is fully up
    var isGearUp: Bool {
        landingGearLayer?.isInactive ?? false
    }

    /// Returns true if a gear animation is in progress
    var isGearAnimating: Bool {
        landingGearLayer?.isAnimating ?? false
    }

    // MARK: - Debug

    /// Prints current animator state for debugging
    func debugPrintState() {
        print("""
        [AircraftAnimator State]
          Gear State: \(gearState)
          Gear Progress: \(String(format: "%.2f", gearAnimationProgress))
          Gear Duration: \(String(format: "%.2f", gearAnimationDuration))s
          Playback State: \(playbackState)
          Channels: \(layerSystem?.channelIDs ?? [])
        """)

        layerSystem?.debugPrintState()
    }
}
