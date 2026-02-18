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
/// internally to manage multiple independent animation layers.
class AircraftAnimator: AnimationController {
    // MARK: - Properties

    /// Reference to the UsdModel containing animation data (skeletons, clips, skins)
    internal weak var model: UsdModel?

    /// Internal layer system that manages animation layers
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

    // MARK: - Landing Gear layer Access

    /// The landing gear layer ID (standard across all aircraft)
    static let landingGearlayerID = "landingGear"

    /// Direct access to the landing gear layer
    // TODO: Using layerSet now:
//    var landingGearlayer: BinaryAnimationLayer? {
//        layerSystem?.layer(Self.landingGearlayerID, as: BinaryAnimationLayer.self)
//    }
    
    var landingGearlayerSet: AnimationLayerSet? {
        layerSystem?.layerSet(Self.landingGearlayerID)
    }

    // MARK: - Gear State (Legacy Compatibility)

    /// Current state of the landing gear (maps to layer state)
//    var gearState: GearState {
//        guard let layer = landingGearlayer else { return .down }
//        switch layer.state {
//        case .inactive: return .up
//        case .activating: return .extending
//        case .active: return .down
//        case .deactivating: return .retracting
//        }
//    }
    
    var gearState: GearState {
        guard let layerSet = landingGearlayerSet else { return .down }
        switch layerSet.state {
            case .inactive: return .up
            case .activating: return .extending
            case .active: return .down
            case .deactivating: return .retracting
        }
    }

    /// Animation progress for the landing gear (0.0 = fully up, 1.0 = fully down)
    var gearAnimationProgress: Float {
        landingGearlayerSet?.progress ?? 1.0
    }

    /// Duration for gear extension/retraction animation in seconds
    var gearAnimationDuration: Float {
        landingGearlayerSet?.transitionDuration ?? 0
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
    func setuplayers() {
        // Base implementation does nothing
        // Subclasses override to register aircraft-specific layers
    }

    // MARK: - layer Management

    /// Register an animation layer
    /// - Parameter layer: The layer to register
    func registerlayer(_ layer: AnimationLayer) {
        layerSystem?.registerlayer(layer)
    }
    
    func registerlayerSet(_ layerSet: AnimationLayerSet) {
        layerSystem?.registerlayerSet(layerSet)
    }

    /// Get a layer by ID
    /// - Parameter id: The layer ID
    /// - Returns: The layer if found
    func layer(_ id: String) -> AnimationLayer? {
        layerSystem?.layer(id)
    }

    /// Get a typed layer by ID
    /// - Parameters:
    ///   - id: The layer ID
    ///   - type: The expected layer type
    /// - Returns: The layer cast to the specified type
    func layer<T: AnimationLayer>(_ id: String, as type: T.Type) -> T? {
        layerSystem?.layer(id, as: type)
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
        guard let layerSet = landingGearlayerSet else {
            print("[AircraftAnimator] No landing gear layer set registered")
            return
        }
        layerSet.activate()
        playbackState = layerSet.isAnimating ? .playing : .stopped
    }

    /// Initiates landing gear retraction
    /// Only works when gear is fully down
    func retractGear() {
        guard let layerSet = landingGearlayerSet else {
            print("[AircraftAnimator] No landing gear layer set registered")
            return
        }
        layerSet.deactivate()
        playbackState = layerSet.isAnimating ? .playing : .stopped
    }

    /// Toggles landing gear between extended and retracted states
    func toggleGear() {
        guard let layerSet = landingGearlayerSet else {
            print("[AircraftAnimator] No landing gear layer set registered")
            return
        }
        layerSet.toggle()
        print("[AircraftAnimator] Toggled Landing Gear")
        playbackState = layerSet.isAnimating ? .playing : .stopped
    }

    /// Returns true if the gear is fully down
    var isGearDown: Bool {
        landingGearlayerSet?.isActive ?? true
    }

    /// Returns true if the gear is fully up
    var isGearUp: Bool {
        landingGearlayerSet?.isInactive ?? false
    }

    /// Returns true if a gear animation is in progress
    var isGearAnimating: Bool {
        landingGearlayerSet?.isAnimating ?? false
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
          layers: \(layerSystem?.layerIDs ?? [])
        """)

        layerSystem?.debugPrintState()
    }
}
