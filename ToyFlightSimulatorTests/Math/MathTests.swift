//
//  MathTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import simd
@testable import ToyFlightSimulator

@Suite("Math.swift", .tags(.math))
struct MathTests {

    // MARK: - Axis constants

    @Test("Axis constants are unit vectors along their respective axes")
    func axisConstants() {
        #expect(X_AXIS == SIMD3<Float>(1, 0, 0))
        #expect(Y_AXIS == SIMD3<Float>(0, 1, 0))
        #expect(Z_AXIS == SIMD3<Float>(0, 0, 1))
    }

    // MARK: - Float radian/degree conversion

    @Test("toRadians converts common angles", arguments: [
        (degrees: Float(0),    expected: Float(0)),
        (degrees: Float(90),   expected: Float.pi / 2),
        (degrees: Float(180),  expected: Float.pi),
        (degrees: Float(360),  expected: 2 * Float.pi),
        (degrees: Float(-90),  expected: -Float.pi / 2),
    ])
    func toRadiansCases(_ pair: (degrees: Float, expected: Float)) {
        #expect(approxEqual(pair.degrees.toRadians, pair.expected))
    }

    @Test("toDegrees is the inverse of toRadians")
    func roundTrip() {
        for deg in stride(from: Float(-360), through: 360, by: 45) {
            #expect(approxEqual(deg.toRadians.toDegrees, deg, tolerance: 1e-3))
        }
    }

}
