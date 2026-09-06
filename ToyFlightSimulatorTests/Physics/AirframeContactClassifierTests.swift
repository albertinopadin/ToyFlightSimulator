//
//  AirframeContactClassifierTests.swift
//  ToyFlightSimulatorTests
//
//  B.6 (B-classification): the pure scrape-vs-impact vocabulary for airframe
//  ground contacts — approach speed along the Contact's B→A normal from the
//  PRE-impact velocity (RigidBody.stepStartVelocity), 2 m/s boundary, strictly
//  greater. The end-to-end check that the wiring sees the arrival and not the
//  bounce is GearSuspensionWorldTests.bellyImpactClassifiesAsCrash.
//

import Testing
import simd
@testable import ToyFlightSimulator

@Suite("Airframe contact classification", .tags(.physics))
struct AirframeContactClassifierTests {
    private func classify(normal: float3, velocity: float3) -> (AirframeContactClass, Float) {
        let speed = AirframeContactClassifier.normalSpeed(contactNormal: normal, preImpactVelocity: velocity)
        return (AirframeContactClassifier.classification(forNormalSpeed: speed), speed)
    }

    @Test("normal speed is the pre-impact approach along the contact normal")
    func normalSpeedMath() {
        // Descending onto level ground: n = up (B→A with the aircraft as A).
        let (cls, speed) = classify(normal: [0, 1, 0], velocity: [30, -5, 0])
        #expect(approxEqual(speed, 5))
        #expect(cls == .impact)
    }

    @Test("fast tangential motion with a gentle sink is a scrape")
    func tangentialIsGentle() {
        let (cls, speed) = classify(normal: [0, 1, 0], velocity: [80, -0.5, 0])
        #expect(cls == .scrape)
        #expect(approxEqual(speed, 0.5))
    }

    @Test("a separating velocity clamps to zero speed: scrape")
    func separatingClampsToZero() {
        let (cls, speed) = classify(normal: [0, 1, 0], velocity: [0, 3, 0])
        #expect(speed == 0)
        #expect(cls == .scrape)
    }

    @Test("exactly the threshold speed is still a scrape")
    func thresholdBoundary() {
        let (cls, _) = classify(normal: [0, 1, 0],
                                velocity: [0, -AirframeContactClassifier.impactSpeedThreshold, 0])
        #expect(cls == .scrape)
    }

    @Test("just past the threshold is an impact, on a tilted normal too")
    func pastThresholdIsImpact() {
        // A sloped surface: only the component along the normal counts.
        let n = simd_normalize(float3(0, 1, 1))
        let (cls, speed) = classify(normal: n, velocity: [0, -2.0, -2.0])
        #expect(approxEqual(speed, 2 * (2 as Float).squareRoot()))
        #expect(cls == .impact)
    }
}
