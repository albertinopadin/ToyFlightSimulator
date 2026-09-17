//
//  AircraftTelemetryTests.swift
//  ToyFlightSimulatorTests
//
//  Metal-free: the snapshot math is a pure static function, and the attitude
//  inputs come from a plain Node driven by the same rotateX/Y/Z calls the
//  aircraft uses, so the sign conventions under test are the engine's own.
//

import Testing
import simd
@testable import ToyFlightSimulator

@Suite("AircraftTelemetry", .tags(.gameObjects, .math))
struct AircraftTelemetryTests {
    /// Degrees of slack for angles read back through Float matrix products.
    private let angleTolerance: Float = 0.01

    private static let zeroSnapshot = AircraftTelemetry(aircraftType: nil,
                                                        heading: 0,
                                                        altitudeInMeters: 0,
                                                        forwardSpeedInMetersPerSecond: 0,
                                                        pitchAngle: 0,
                                                        rollAngle: 0)

    /// A scene-root node posed with the aircraft's own rotation calls:
    /// heading about up, then pitch about the new right axis, then bank about
    /// the new nose. Signs follow Aircraft.applyAttitudeRates, where positive
    /// pitch and bank inputs apply negative rotateX / rotateZ; heading is
    /// authored directly (rotateY(+ψ) turns the nose toward +X).
    private func posedNode(headingDegrees: Float = 0,
                           pitchDegrees: Float = 0,
                           bankDegrees: Float = 0,
                           scale: Float = 1) -> Node {
        let node = Node(name: "posed")
        node.setScale(scale)
        node.rotateY(headingDegrees.toRadians)
        node.rotateX(-pitchDegrees.toRadians)
        node.rotateZ(-bankDegrees.toRadians)
        return node
    }

    private func angles(of node: Node) -> AircraftTelemetry.AttitudeAngles {
        AircraftTelemetry.attitudeAngles(forward: node.getFwdVector(),
                                         right: node.getRightVector(),
                                         up: node.getUpVector())
    }

    private func expectAngles(_ angles: AircraftTelemetry.AttitudeAngles,
                              pitch: Float, roll: Float, heading: Float,
                              sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(approxEqual(angles.pitch, pitch, tolerance: angleTolerance), "pitch \(angles.pitch)", sourceLocation: sourceLocation)
        #expect(angles.roll.map { approxEqual($0, roll, tolerance: angleTolerance) } == true, "roll \(String(describing: angles.roll))", sourceLocation: sourceLocation)
        #expect(angles.heading.map { approxEqual($0, heading, tolerance: angleTolerance) } == true, "heading \(String(describing: angles.heading))", sourceLocation: sourceLocation)
    }

    // MARK: - Attitude angles

    @Test("Level with the nose along +Z reads pitch 0, bank 0, heading 0")
    func levelReadsZero() {
        expectAngles(angles(of: posedNode()), pitch: 0, roll: 0, heading: 0)
    }

    @Test("A positive pitch input (rotateX negative) reads nose-up positive pitch")
    func pitchSign() {
        expectAngles(angles(of: posedNode(pitchDegrees: 10)), pitch: 10, roll: 0, heading: 0)
        expectAngles(angles(of: posedNode(pitchDegrees: -25)), pitch: -25, roll: 0, heading: 0)
    }

    @Test("A positive roll input (rotateZ negative) reads right-wing-down positive bank")
    func bankSign() {
        expectAngles(angles(of: posedNode(bankDegrees: 20)), pitch: 0, roll: 20, heading: 0)
        expectAngles(angles(of: posedNode(bankDegrees: -120)), pitch: 0, roll: -120, heading: 0)
    }

    @Test("Heading is a compass: nose toward +X reads 90, nose left of +Z wraps to 330")
    func headingIsCompass() {
        expectAngles(angles(of: posedNode(headingDegrees: 90)), pitch: 0, roll: 0, heading: 90)
        // The engine's positive yaw input is rotateY(-rate·dt): nose toward −X.
        expectAngles(angles(of: posedNode(headingDegrees: -30)), pitch: 0, roll: 0, heading: 330)
        expectAngles(angles(of: posedNode(headingDegrees: -180)), pitch: 0, roll: 0, heading: 180)
    }

    @Test("Composed heading 30, pitch 10, bank 20 reads back exactly")
    func composedAttitudeRoundTrips() {
        expectAngles(angles(of: posedNode(headingDegrees: 30, pitchDegrees: 10, bankDegrees: 20)),
                     pitch: 10, roll: 20, heading: 30)
        expectAngles(angles(of: posedNode(headingDegrees: -70, pitchDegrees: -25, bankDegrees: -120)),
                     pitch: -25, roll: -120, heading: 290)
    }

    @Test("Angles ignore node scale (basis vectors are normalized)")
    func scaleInvariant() {
        expectAngles(angles(of: posedNode(headingDegrees: 30, pitchDegrees: 10, bankDegrees: 20, scale: 3)),
                     pitch: 10, roll: 20, heading: 30)
    }

    @Test("Inverted flight reads bank ±180 with pitch 0 and the heading unchanged")
    func invertedFlight() {
        let a = angles(of: posedNode(headingDegrees: 30, bankDegrees: 180))
        #expect(approxEqual(a.pitch, 0, tolerance: angleTolerance))
        #expect(a.roll.map { approxEqual(abs($0), 180, tolerance: angleTolerance) } == true)
        #expect(a.heading.map { approxEqual($0, 30, tolerance: angleTolerance) } == true)
    }

    @Test("Past the vertical the readout folds: pitch 120 reads 60 / 180 / reciprocal heading")
    func overTheTopFolds() {
        let a = angles(of: posedNode(headingDegrees: 30, pitchDegrees: 120))
        #expect(approxEqual(a.pitch, 60, tolerance: angleTolerance))
        #expect(a.roll.map { approxEqual(abs($0), 180, tolerance: angleTolerance) } == true)
        #expect(a.heading.map { approxEqual($0, 210, tolerance: angleTolerance) } == true)
    }

    @Test("Straight up reads pitch 90 with heading and bank undefined")
    func verticalIsUndefined() {
        let a = angles(of: posedNode(headingDegrees: 30, pitchDegrees: 90))
        #expect(approxEqual(a.pitch, 90, tolerance: angleTolerance))
        #expect(a.roll == nil)
        #expect(a.heading == nil)
        let down = angles(of: posedNode(pitchDegrees: -90))
        #expect(approxEqual(down.pitch, -90, tolerance: angleTolerance))
        #expect(down.heading == nil)
    }

    @Test("Just short of vertical the angles are still defined and accurate")
    func nearVerticalStaysDefined() {
        expectAngles(angles(of: posedNode(headingDegrees: 30, pitchDegrees: 89.9, bankDegrees: 20)),
                     pitch: 89.9, roll: 20, heading: 30)
    }

    @Test("Heading stays in [0, 360): a nose a hair left of +Z reads 0, not 360")
    func headingNeverReaches360() {
        // atan2 gives −5.7e-6°; adding 360 rounds to exactly 360 in Float.
        let a = AircraftTelemetry.attitudeAngles(forward: normalize(float3(-1e-7, 0, 1)),
                                                 right: normalize(float3(1, 0, 1e-7)),
                                                 up: float3(0, 1, 0))
        #expect(a.heading == 0)
    }

    // MARK: - Snapshot assembly

    @Test("Forward speed is the velocity projected on the nose, not world Z")
    func forwardSpeedIsProjection() {
        let node = posedNode(headingDegrees: 90)   // nose along +X
        func speed(_ velocity: float3) -> Float {
            AircraftTelemetry.make(aircraftType: nil,
                                   forward: node.getFwdVector(), right: node.getRightVector(), up: node.getUpVector(),
                                   velocity: velocity, worldPosition: .zero,
                                   previous: Self.zeroSnapshot).forwardSpeedInMetersPerSecond
        }
        #expect(approxEqual(speed(float3(50, 0, 0)), 50, tolerance: 1e-3))
        #expect(approxEqual(speed(float3(0, 0, 50)), 0, tolerance: 1e-3))
        #expect(approxEqual(speed(float3(-10, 30, 0)), -10, tolerance: 1e-3))
    }

    @Test("Altitude is world y and the aircraft type passes through")
    func altitudeAndType() {
        let node = posedNode()
        let snapshot = AircraftTelemetry.make(aircraftType: .f35,
                                              forward: node.getFwdVector(), right: node.getRightVector(), up: node.getUpVector(),
                                              velocity: .zero, worldPosition: float3(5, 1234.5, -7),
                                              previous: Self.zeroSnapshot)
        #expect(snapshot.altitudeInMeters == 1234.5)
        #expect(snapshot.aircraftType == .f35)
        #expect(snapshot.forwardSpeedInMetersPerSecond == 0)
    }

    @Test("With the nose vertical the snapshot holds the previous heading and bank")
    func verticalHoldsPrevious() {
        let node = posedNode(headingDegrees: 30, pitchDegrees: 90)
        let previous = AircraftTelemetry(aircraftType: .f22, heading: 123, altitudeInMeters: 0,
                                         forwardSpeedInMetersPerSecond: 0, pitchAngle: 45, rollAngle: 45)
        let snapshot = AircraftTelemetry.make(aircraftType: .f22,
                                              forward: node.getFwdVector(), right: node.getRightVector(), up: node.getUpVector(),
                                              velocity: .zero, worldPosition: .zero, previous: previous)
        #expect(snapshot.heading == 123)
        #expect(snapshot.rollAngle == 45)
        #expect(approxEqual(snapshot.pitchAngle, 90, tolerance: angleTolerance))
    }

    @Test("Display units: 100 m/s is 194.4 kn and 223.7 mph, 1000 m is 3280.8 ft")
    func displayUnits() {
        let snapshot = AircraftTelemetry(aircraftType: nil, heading: 0, altitudeInMeters: 1000,
                                         forwardSpeedInMetersPerSecond: 100, pitchAngle: 0, rollAngle: 0)
        #expect(approxEqual(snapshot.speedInKnots, 194.384, tolerance: 0.01))
        #expect(approxEqual(snapshot.speedInMph, 223.694, tolerance: 0.01))
        #expect(approxEqual(snapshot.altitudeInFeet, 3280.84, tolerance: 0.01))
    }
}
