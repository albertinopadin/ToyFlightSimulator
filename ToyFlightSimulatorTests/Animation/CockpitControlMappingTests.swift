//
//  CockpitControlMappingTests.swift
//  ToyFlightSimulatorTests
//

import Testing
@testable import ToyFlightSimulator

/// The cockpit throttle's detent mapping and the gear-handle rule (Milestone 4 of
/// plans/claude/f22_cockpit_first_person_view_2026-09-25.md). Metal-free: pure static functions,
/// no model, no animator.
@Suite("F-22 cockpit control mapping", .tags(.animation))
struct CockpitControlMappingTests {
    /// The worked example in the plan rounds angles to 0.01° and channel values to 0.001.
    static let angleTolerance_rad = Float(0.01).toRadians
    static let channelValueTolerance: Float = 1e-3

    struct ThrottleCase: Sendable, CustomTestStringConvertible {
        let throttle: Float
        let leverAngle_deg: Float
        let channelValue: Float
        var testDescription: String { "throttle \(throttle)" }
    }

    @Test("throttle maps through the detents: IDLE at 0, MIL at 0.8, AB at 1",
          arguments: [
            ThrottleCase(throttle: 0.0, leverAngle_deg: 5.74, channelValue: 0.329),      // IDLE
            ThrottleCase(throttle: 0.4, leverAngle_deg: 0.00, channelValue: 0.000),      // lever vertical
            ThrottleCase(throttle: 0.8, leverAngle_deg: -5.74, channelValue: -0.329),    // MIL
            ThrottleCase(throttle: 0.9, leverAngle_deg: -11.60, channelValue: -0.664),   // halfway to AB
            ThrottleCase(throttle: 1.0, leverAngle_deg: -17.46, channelValue: -1.000),   // AB
          ])
    func throttleWorkedExample(_ testCase: ThrottleCase) {
        let leverAngle_rad = F22CockpitAnimationConfig.throttleLeverAngle(for: testCase.throttle)
        #expect(approxEqual(leverAngle_rad, testCase.leverAngle_deg.toRadians, tolerance: Self.angleTolerance_rad))
        let channelValue = F22CockpitAnimationConfig.throttleChannelValue(for: testCase.throttle)
        #expect(approxEqual(channelValue, testCase.channelValue, tolerance: Self.channelValueTolerance))
    }

    @Test("a negative throttle (keyboard S is -1) reads as IDLE", arguments: [Float(-0.5), -1.0])
    func throttleBelowZeroIsIdle(throttle: Float) {
        #expect(F22CockpitAnimationConfig.throttleLeverAngle(for: throttle)
                == F22CockpitAnimationConfig.idleThrottleSpace)
    }

    @Test("a throttle above 1 reads as AB")
    func throttleAboveOneIsAfterburner() {
        #expect(approxEqual(F22CockpitAnimationConfig.throttleLeverAngle(for: 1.7),
                            F22CockpitAnimationConfig.afterburnerThrottleSpace, tolerance: 1e-6))
    }

    /// The lever reaches the MIL gate at exactly the throttle where F22.doUpdate lights the
    /// afterburners, because both read F22.milPowerThrottleThreshold.
    @Test("the MIL detent sits at the afterburner threshold")
    func milDetentSitsAtTheAfterburnerThreshold() {
        let leverAngle_rad = F22CockpitAnimationConfig.throttleLeverAngle(for: F22.milPowerThrottleThreshold)
        #expect(approxEqual(leverAngle_rad, F22CockpitAnimationConfig.milThrottleSpace, tolerance: 1e-6))
    }

    /// The handle follows the command, so it moves as soon as the gear starts to extend or retract.
    @Test("the gear handle points DN while the gear is down or extending",
          arguments: [GearState.down, .extending])
    func gearHandleDownWhileGearCommandedDown(gearState: GearState) {
        #expect(F22CockpitAnimator.gearHandleCommandedDown(exteriorGearState: gearState))
    }

    @Test("the gear handle points UP while the gear is up or retracting",
          arguments: [GearState.up, .retracting])
    func gearHandleUpWhileGearCommandedUp(gearState: GearState) {
        #expect(!F22CockpitAnimator.gearHandleCommandedDown(exteriorGearState: gearState))
    }
}
