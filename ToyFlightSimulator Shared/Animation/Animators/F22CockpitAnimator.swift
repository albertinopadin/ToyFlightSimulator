//
//  F22CockpitAnimator.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/26.
//

/// Moves the F-22 cockpit's side-stick, throttles, rudder pedals and gear handle from pilot input
/// (Milestone 4 of plans/claude/f22_cockpit_first_person_view_2026-09-25.md). Owned and driven by
/// `Aircraft` (`cockpitAnimator`), on the UpdateThread.
///
/// The cockpit `UsdModel` is shared by every F-22 instance, so its pose is too: only the
/// player-controlled aircraft sets values (`Aircraft.updateCockpitControls`).
final class F22CockpitAnimator: AircraftAnimator {
    // Looked up once in setupLayers so the per-tick setters do no string lookups. A channel stays
    // nil when its joint is missing from the model (the config prints a warning), and its setter
    // then does nothing.
    var sideStickRollChannel: ProceduralAnimationChannel?
    var sideStickPitchChannel: ProceduralAnimationChannel?
    var throttleChannel: ProceduralAnimationChannel?
    var rudderPedalsChannel: ProceduralAnimationChannel?
    var gearHandleChannel: ProceduralAnimationChannel?

    override init(model: UsdModel) {
        super.init(model: model)
        setupLayers()

        // Force initial pose update to ensure model starts in correct state
        layerSystem?.forceUpdateAllPoses()

        print("[F22CockpitAnimator] Initialized with \(layerSystem?.channelCount ?? 0) channels")
    }

    override func setupLayers() {
        guard let model = model else {
            print("[F22CockpitAnimator] Warning: No model available for layer setup")
            return
        }

        let layers = F22CockpitAnimationConfig.createLayers(for: model)
        for layer in layers {
            registerLayer(layer)
            print("[F22CockpitAnimator] Registered layer: \(layer.id)")

            for channel in layer.channels {
                switch channel.id {
                    case F22CockpitAnimationConfig.sideStickRollChannelID:
                        self.sideStickRollChannel = channel as? ProceduralAnimationChannel
                    case F22CockpitAnimationConfig.sideStickPitchChannelID:
                        self.sideStickPitchChannel = channel as? ProceduralAnimationChannel
                    case F22CockpitAnimationConfig.throttleChannelID:
                        self.throttleChannel = channel as? ProceduralAnimationChannel
                    case F22CockpitAnimationConfig.rudderPedalsChannelID:
                        self.rudderPedalsChannel = channel as? ProceduralAnimationChannel
                    case F22CockpitAnimationConfig.gearHandleChannelID:
                        self.gearHandleChannel = channel as? ProceduralAnimationChannel
                    default:
                        continue
                }
            }
        }
    }

    /// - Parameters:
    ///   - pitch: `ControlInput.pitch`, −1…1; + = stick aft (pull), which the down arrow gives.
    ///   - roll: `ControlInput.roll`, −1…1; + = stick right (right arrow).
    func setSideStick(pitch: Float, roll: Float) {
        sideStickPitchChannel?.setValue(pitch)
        sideStickRollChannel?.setValue(roll)
    }

    /// - Parameter input: `ControlInput.throttle`. Mapped through the detents to a lever angle
    ///   (`F22CockpitAnimationConfig.throttleChannelValue`); a negative input (keyboard S) is IDLE.
    func setThrottles(input: Float) {
        throttleChannel?.setValue(F22CockpitAnimationConfig.throttleChannelValue(for: input))
    }

    /// - Parameter input: `ControlInput.yaw`, −1…1; + (Q, nose left) pushes the left pedal
    ///   forward and the right pedal aft.
    func setRudderPedals(input: Float) {
        rudderPedalsChannel?.setValue(input)
    }

    /// - Parameter gearDown: true = handle DN (the rest pose), false = UP, 33.40° about the
    ///   handle's pivot.
    func setGearHandle(gearDown: Bool) {
        gearHandleChannel?.setValue(gearDown ? 0 : 1)
    }

    /// Whether the gear handle should point DN for the exterior gear's state. The handle follows
    /// the command, not the gear: it moves as soon as the gear starts extending or retracting, as
    /// the real lever leads the gear. Static and pure so it can be tested without Metal.
    static func gearHandleCommandedDown(exteriorGearState: GearState) -> Bool {
        return exteriorGearState == .down || exteriorGearState == .extending
    }
}
