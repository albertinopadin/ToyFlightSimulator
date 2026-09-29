//
//  F22CockpitAnimationConfig.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/26.
//

/// Animation layers for the F-22 cockpit's controls (Milestone 4 of
/// plans/claude/f22_cockpit_first_person_view_2026-09-25.md). Every moving part is rigidly skinned
/// to one single-axis joint (the rig in the asset's `bc_controls.py`), so each joint is one
/// `ProceduralJointConfig`, as for the CGTrader F-22's control surfaces.
///
/// Axes are in the joint's local frame, which equals the cockpit file's native frame (Blender:
/// +X right, +Y forward, +Z up; every joint's rest rotation is the identity).
///
/// Signs: `float4x4(rotateAbout:byAngle:)` is the transpose of the right-handed axis-angle
/// matrix, so a positive angle turns a part clockwise seen from the tip of its axis (the
/// left-hand rule). About native +X, a positive angle tips a part's top forward. Each `inverted`
/// flag below makes a positive input move the part in its positive direction: stick right and
/// aft, lever forward, left pedal forward. The direction tests in `CockpitAnimatorTests` check
/// every joint through the skin palette.
struct F22CockpitAnimationConfig {
    // Travel, from the rig (`bc_controls.py`). The real F-22 side-stick is force-sensing with about
    // 1/4 in of throw, so the stick's ±12° is a visual convention.
    static let sideStickMaxDeflection = Float(12).toRadians
    /// The throttle channel's full scale: channel value −1 is the AB detent.
    static let throttleMaxDeflection = Float(17.46).toRadians
    // Throttle detent angles about the lever's local X, forward negative. The lever pivots 0.20 m
    // below the console top, and the detents are printed 0.02 m (IDLE, MIL) and 0.06 m (AB) either
    // side of the slot centre: asin(0.02 / 0.20) = 5.74°, asin(0.06 / 0.20) = 17.46°.
    static let idleThrottleSpace = Float(5.74).toRadians
    static let milThrottleSpace = Float(-5.74).toRadians
    static let afterburnerThrottleSpace = Float(-17.46).toRadians
    /// DN (rest) to UP. The knob sits 0.030 m below the slot centre, 0.10 m from the pivot, so it
    /// rests atan(0.030 / 0.10) = 16.70° below and UP is twice that.
    static let gearLeverDeflection = Float(33.40).toRadians
    static let rudderPedalsMaxDeflection = Float(10).toRadians

    static let sideStickRollAxis: float3 = [0, 1, 0]
    static let sideStickPitchAxis: float3 = [1, 0, 0]
    static let throttleJointAxis: float3 = [1, 0, 0]
    static let rudderPedalJointAxis: float3 = [1, 0, 0]
    static let gearHandleJointAxis: float3 = [1, 0, 0]
    
    // Read by the layer builders below and by F22CockpitAnimator, which looks the channels up by ID.
    static let sideStickRollChannelID = "sideStickRoll"
    static let sideStickPitchChannelID = "sideStickPitch"
    static let throttleChannelID = "cockpitThrottle"
    static let rudderPedalsChannelID = "rudderPedals"
    static let gearHandleChannelID = "gearHandle"
    
    static func createLayers(for model: UsdModel) -> [AnimationLayer] {
        var layers: [AnimationLayer] = []
        layers.append(createSideStickLayer(for: model))
        layers.append(createThrottleLayer(for: model))
        layers.append(createRudderPedalsLayer(for: model))
        layers.append(createGearHandleLayer(for: model))
        return layers
    }
    
    typealias JointPath<Suffix> = String?

    /// Finds one joint path per suffix and returns them as a tuple, in the same order as the suffixes:
    ///
    ///     let (rollPath, pitchPath) = findJointPaths(in: model, suffixes: "StickRoll", "StickPitch")
    ///
    /// Each element is the first joint path, across all of the model's skeletons, that ends with its
    /// suffix, or `nil` if no joint does. The match is case-sensitive and compares characters, not
    /// whole path components: the suffix "Roll" would also match "CockpitRoot/StickRoll".
    ///
    /// Why parameter packs:
    /// A variadic parameter (`suffixes: String...`) accepts any number of arguments, but inside the
    /// function it is one `[String]`, and Swift has no variadic return type, because a tuple's length
    /// must be known at compile time. Parameter packs (Swift 5.9) make a function generic over how
    /// many arguments it takes, not only over their types. The compiler then knows the count at each
    /// call site and can return a tuple of exactly that length.
    ///
    /// Terms:
    /// - Type parameter pack, `each Suffix`: a list of zero or more generic types, one per argument.
    ///   A call with "StickRoll", "StickPitch" binds it to [String, String]. `: StringProtocol`
    ///   constrains every type in the list.
    /// - Value parameter pack, `suffixes: repeat each Suffix`: the argument values, one per type in
    ///   the pack.
    /// - Pack expansion, `repeat <pattern>`: repeats the pattern once per pack element. Inside the
    ///   pattern, `each suffixes` (a value) and `each Suffix` (a type) stand for the current element.
    ///   The pattern must reference at least one pack; that reference tells the compiler how many
    ///   copies to make.
    ///
    /// How this function uses them:
    /// 1. The return type `(repeat JointPath<each Suffix>)` is one `JointPath` per suffix, wrapped in
    ///    a tuple. For two suffixes it becomes `(JointPath<String>, JointPath<String>)`, which is
    ///    `(String?, String?)`.
    /// 2. `JointPath<Suffix>` (above) ignores its parameter and is always `String?`. It exists because
    ///    `-> (repeat String?)` does not compile: "pack expansion 'String?' must contain at least one
    ///    pack reference". `JointPath<each Suffix>` references the pack, so the compiler can count,
    ///    and each element still resolves to `String?`. This workaround is our own, not from the
    ///    references below; it was verified with swiftc 6.4.
    /// 3. The body flattens every skeleton's joint paths into one array once. The return expression
    ///    `(repeat ...)` then runs the `first { $0.hasSuffix(...) }` search once per suffix and puts
    ///    each result at that suffix's position in the tuple.
    ///
    /// Edge cases:
    /// - One suffix: a one-element pack expansion unwraps to its element, so the result is a plain
    ///   `String?`, not a one-element tuple.
    /// - No suffixes: the result is `()`.
    /// - Destructuring into the wrong number of names is a compile error ("tuples have a different
    ///   number of elements"), unlike indexing past the end of an array, which fails at runtime.
    /// - `model.skeletons` is a Dictionary, whose `.values` order can change between launches. If
    ///   two skeletons each have a joint ending with the same suffix, which one is returned can
    ///   change too. The cockpit model has one skeleton (`CockpitRig`), so this does not arise today.
    ///
    /// References:
    /// - SE-0393, "Value and Type Parameter Packs" (implemented in Swift 5.9). The specification of
    ///   `each`, `repeat`, the pack-reference rule, and the one-element unwrap.
    ///   https://github.com/swiftlang/swift-evolution/blob/main/proposals/0393-parameter-packs.md
    /// - WWDC23 session 10168, "Generalize APIs with parameter packs". Apple's walkthrough, building
    ///   a variadic generic API step by step.
    ///   https://developer.apple.com/videos/play/wwdc2023/10168/
    /// - "Swift 5.9 Released", section "Parameter packs". A short overview that links SE-0393 and
    ///   the follow-up proposals SE-0398 (generic types over packs) and SE-0399 (tuples of packs).
    ///   https://www.swift.org/blog/swift-5.9-released/
    static func findJointPaths<each Suffix: StringProtocol>(
        in model: UsdModel,
        suffixes: repeat each Suffix
    ) -> (repeat JointPath<each Suffix>) {
        let allJointPaths = model.skeletons.values.flatMap { $0.jointPaths }
        return (repeat allJointPaths.first { $0.hasSuffix(each suffixes) })
    }
    
    static func createSideStickLayer(for model: UsdModel) -> AnimationLayer {
        let (stickRollPath, stickPitchPath) = findJointPaths(in: model, suffixes: "StickRoll", "StickPitch")

        var channels: [ProceduralAnimationChannel] = []

        if let roll = stickRollPath {
            let rollJointConfig = ProceduralJointConfig(
                jointPath: roll,
                axis: sideStickRollAxis,
                maxDeflection: sideStickMaxDeflection,
                inverted: true      // + roll input (right arrow) = stick right
            )
            
            let mask = AnimationMask(jointPaths: [rollJointConfig.jointPath])
            
            let rollChannel = ProceduralAnimationChannel(id: sideStickRollChannelID,
                                                         mask: mask,
                                                         range: (-1.0, 1.0),
                                                         transitionSpeed: 8.0,  // Fast response for control surfaces
                                                         initialValue: 0.0,
                                                         jointConfigs: [rollJointConfig])
            
            channels.append(rollChannel)
        } else {
            print("[F22CockpitAnimationConfig] Warning: Side Stick Roll joint not found in skeleton")
        }

        if let pitch = stickPitchPath {
            let pitchJointConfig = ProceduralJointConfig(
                jointPath: pitch,
                axis: sideStickPitchAxis,
                maxDeflection: sideStickMaxDeflection,
                inverted: true      // + pitch input (down arrow) = stick aft
            )
            
            let mask = AnimationMask(jointPaths: [pitchJointConfig.jointPath])
            
            let pitchChannel = ProceduralAnimationChannel(id: sideStickPitchChannelID,
                                                          mask: mask,
                                                          range: (-1.0, 1.0),
                                                          transitionSpeed: 8.0,
                                                          initialValue: 0.0,
                                                          jointConfigs: [pitchJointConfig])
            
            channels.append(pitchChannel)
        } else {
            print("[F22CockpitAnimationConfig] Warning: Side Stick Pitch joint not found in skeleton")
        }
        
        return AnimationLayer(id: AnimationLayerID.cockpitStick.rawValue, channels: channels)
    }
    
    static func createThrottleLayer(for model: UsdModel) -> AnimationLayer {
        let (leftThrottleJointPath, rightThrottleJointPath) = findJointPaths(in: model,
                                                                             suffixes: "ThrottleLeft", "ThrottleRight")

        // Both levers turn together on one channel. Its value comes from throttleChannelValue,
        // which is − for forward, and inverted turns − into a forward (top-forward) rotation.
        var jointConfigs: [ProceduralJointConfig] = []

        if let leftThrottle = leftThrottleJointPath {
            jointConfigs.append(ProceduralJointConfig(
                jointPath: leftThrottle,
                axis: throttleJointAxis,
                maxDeflection: throttleMaxDeflection,
                inverted: true
            ))
        } else {
            print("[F22CockpitAnimationConfig] Warning: Left Throttle joint not found in skeleton")
        }

        if let rightThrottle = rightThrottleJointPath {
            jointConfigs.append(ProceduralJointConfig(
                jointPath: rightThrottle,
                axis: throttleJointAxis,
                maxDeflection: throttleMaxDeflection,
                inverted: true
            ))
        } else {
            print("[F22CockpitAnimationConfig] Warning: Right Throttle joint not found in skeleton")
        }

        let allPaths = jointConfigs.map { $0.jointPath }
        let mask = AnimationMask(jointPaths: allPaths)

        let channel = ProceduralAnimationChannel(
            id: throttleChannelID,
            mask: mask,
            range: (-1.0, 1.0),
            transitionSpeed: 3.0,
            initialValue: 0.0,
            jointConfigs: jointConfigs
        )

        return AnimationLayer(id: AnimationLayerID.cockpitThrottle.rawValue, channels: [channel])
    }
    
    static func createRudderPedalsLayer(for model: UsdModel) -> AnimationLayer {
        let (leftPedalJointPath, rightPedalJointPath) = findJointPaths(in: model, suffixes: "PedalLeft", "PedalRight")

        // One channel for both pedals: pushing one forward brings the other aft. Each pedal hangs
        // from a hinge at its top, so a positive angle swings its foot aft; the left pedal is
        // inverted, so + yaw (Q, nose left) pushes it forward and the right pedal aft.
        var jointConfigs: [ProceduralJointConfig] = []

        if let left = leftPedalJointPath {
            jointConfigs.append(ProceduralJointConfig(
                jointPath: left,
                axis: rudderPedalJointAxis,
                maxDeflection: rudderPedalsMaxDeflection,
                inverted: true
            ))
        } else {
            print("[F22CockpitAnimationConfig] Warning: Left Rudder Pedal joint not found in skeleton")
        }

        if let right = rightPedalJointPath {
            jointConfigs.append(ProceduralJointConfig(
                jointPath: right,
                axis: rudderPedalJointAxis,
                maxDeflection: rudderPedalsMaxDeflection,
                inverted: false
            ))
        } else {
            print("[F22CockpitAnimationConfig] Warning: Right Rudder Pedal joint not found in skeleton")
        }

        let allPaths = jointConfigs.map { $0.jointPath }
        let mask = AnimationMask(jointPaths: allPaths)

        let channel = ProceduralAnimationChannel(
            id: rudderPedalsChannelID,
            mask: mask,
            range: (-1.0, 1.0),
            transitionSpeed: 4.0,
            initialValue: 0.0,
            jointConfigs: jointConfigs
        )

        return AnimationLayer(id: AnimationLayerID.cockpitRudderPedals.rawValue, channels: [channel])
    }
    
    static func createGearHandleLayer(for model: UsdModel) -> AnimationLayer {
        let (gearHandleJointPath) = findJointPaths(in: model, suffixes: "GearHandle")

        var channels: [ProceduralAnimationChannel] = []

        if let gearHandle = gearHandleJointPath {
            let gearHandleJointConfig = ProceduralJointConfig(
                jointPath: gearHandle,
                axis: gearHandleJointAxis,
                maxDeflection: gearLeverDeflection,
                inverted: false     // value 1 = +33.40°: the knob, aft of the pivot, swings up
            )
            
            let mask = AnimationMask(jointPaths: [gearHandleJointConfig.jointPath])
            
            let channel = ProceduralAnimationChannel(
                id: gearHandleChannelID,
                mask: mask,
                range: (0, 1),
                transitionSpeed: 3.0,
                initialValue: 0.0,
                jointConfigs: [gearHandleJointConfig]
            )
            channels.append(channel)
        } else {
            print("[F22CockpitAnimationConfig] Warning: Gear Handle joint not found in skeleton")
        }

        return AnimationLayer(id: AnimationLayerID.cockpitGearHandle.rawValue, channels: channels)
    }
    
    /// The throttle lever's angle about its local X for a throttle input, in radians, forward
    /// negative. Piecewise linear through the detents: IDLE at 0, MIL at
    /// `F22.milPowerThrottleThreshold` (the throttle where the afterburners light), AB at 1. The
    /// two pieces have different slopes because 0…0.8 covers 11.48° and 0.8…1 covers 11.72°.
    /// Input is clamped to 0…1, so the keyboard's −1 (S) reads as IDLE.
    /// Example: 0.9 → −5.74° + (−11.72°) × 0.5 = −11.60°.
    static func throttleLeverAngle(for input: Float) -> Float {
        let throttle = input.clamp(min: 0, max: 1)
        let milPower = F22.milPowerThrottleThreshold
        if throttle <= milPower {
            return idleThrottleSpace + (milThrottleSpace - idleThrottleSpace) * (throttle / milPower)
        } else {
            return milThrottleSpace + (afterburnerThrottleSpace - milThrottleSpace) * ((throttle - milPower) / (1 - milPower))
        }
    }
    
    /// The throttle channel's value for a throttle input: the lever angle divided by the channel's
    /// full scale, which the channel multiplies back. IDLE +0.329, MIL −0.329, AB −1.
    static func throttleChannelValue(for input: Float) -> Float {
        return throttleLeverAngle(for: input) / throttleMaxDeflection
    }
}
