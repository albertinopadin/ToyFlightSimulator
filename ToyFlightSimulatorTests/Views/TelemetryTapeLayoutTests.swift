//
//  TelemetryTapeLayoutTests.swift
//  ToyFlightSimulatorTests
//
//  Metal-free: the HUD tapes' geometry is a handful of pure static functions
//  on TelemetryTapeLayout (Shared/Views), so the compass wrap, the readout
//  rounding, the tick placement along both axes and the centre-line clearance
//  are pinned here without a view, a window or a telemetry store. The heading
//  numbers are the worked example in
//  debugging/claude/heading_tape_centered_no_labels_2026-09-18.md; the
//  vertical numbers are the speed and altitude tapes at their shipped spans.
//

import Foundation
import Testing
@testable import ToyFlightSimulator

@Suite("TelemetryTapeLayout", .tags(.math))
struct TelemetryTapeLayoutTests {
    /// The doc's worked example: a 600-pt strip showing ±30°, so 10 pt per degree.
    private let centerX: CGFloat = 300
    private let pointsPerDegree: Float = 10
    private let labelStepDegrees = 5
    private let clearanceDegrees: Float = 0.5
    
    /// The speed tape at a round size: a 1000-pt strip showing ±100 kt, so 5 pt per knot.
    private let centerY: CGFloat = 500
    private let pointsPerKnot: Float = 5
    private let labelStepKnots = 50
    private let clearanceKnots: Float = 2

    // MARK: - Heading tape (horizontal)

    @Test("Heading labels wrap through north in both directions")
    func wrappedHeadingLabelWrapsThroughNorth() {
        let cases: [(degree: Int, label: Int)] = [
            (-360, 0), (-10, 350), (-1, 359), (0, 0), (359, 359), (360, 0), (365, 5), (720, 0),
        ]
        for (degree, label) in cases {
            #expect(TelemetryTapeLayout.wrappedHeadingLabel(degree: degree) == label, "degree \(degree)")
        }
    }

    @Test("Heading readout rounds to the nearest degree and shows north as 0, like the labels")
    func headingReadoutRoundsAndWraps() {
        let cases: [(heading: Float, readout: Int)] = [
            (0, 0), (0.4, 0), (179.5, 180), (357.5, 358), (359.4, 359), (359.6, 0),
        ]
        for (heading, readout) in cases {
            // the composition HeadingTape uses: round, then wrap like a label
            let rounded = TelemetryTapeLayout.readout(heading)
            #expect(TelemetryTapeLayout.wrappedHeadingLabel(degree: rounded) == readout, "heading \(heading)")
        }
    }

    @Test("Tick placement reproduces the worked example at 357.5°")
    func tickPlacementWorkedExample() {
        let heading: Float = 357.5
        // 300 + (degree − 357.5) × 10; every value is exact in binary floating point
        #expect(tickX(degree: 350, heading: heading) == 225)
        #expect(tickX(degree: 360, heading: heading) == 325)
        #expect(tickX(degree: 370, heading: heading) == 425)
    }

    @Test("The current heading's tick sits on the lubber line, and a right turn slides ticks left")
    func currentHeadingIsCentredAndRightTurnSlidesLeft() {
        #expect(tickX(degree: 45, heading: 45) == centerX)
        let xBeforeTurn = tickX(degree: 50, heading: 45)
        let xAfterOneDegreeRight = tickX(degree: 50, heading: 46)
        #expect(xAfterOneDegreeRight == xBeforeTurn - CGFloat(pointsPerDegree))
    }

    @Test("Candidate ticks cover the visible window plus one label step per side, across the seam")
    func candidateTicksCoverTheWindow() {
        #expect(TelemetryTapeLayout.candidateTicks(currentTelemetryValue: 0,
                                                   halfSpanUnits: 30,
                                                   labelStepUnits: labelStepDegrees) == -35...35)

        let acrossNorth = TelemetryTapeLayout.candidateTicks(currentTelemetryValue: 357.5,
                                                             halfSpanUnits: 30,
                                                             labelStepUnits: labelStepDegrees)
        #expect(acrossNorth == 322...393)
        // every whole degree inside the window 327.5…387.5 is a candidate
        #expect(acrossNorth.contains(328) && acrossNorth.contains(387))

        // the window's edges land on the strip's edges: at heading 30 the ±30° window is 0…60,
        // which the 600-pt strip maps to x = 0 and x = 600
        #expect(tickX(degree: 0, heading: 30) == 0)
        #expect(tickX(degree: 60, heading: 30) == 600)
    }

    @Test("Lubber line clearance: within half a degree of a labeled tick, on either side")
    func nearLabeledTickBoundaries() {
        let cases: [(heading: Float, near: Bool)] = [
            (0, true), (0.3, true), (0.5, false), (2.5, false), (4.5, false),
            (4.7, true), (5.3, true), (5.7, false), (359.4, false), (359.6, true),
        ]
        for (heading, near) in cases {
            #expect(TelemetryTapeLayout.isNearLabeledTick(currentTelemetryValue: heading,
                                                          labelStepUnits: labelStepDegrees,
                                                          clearanceUnits: clearanceDegrees) == near,
                    "heading \(heading)")
        }
    }

    /// The two-part expression the heading tape shipped with. Its first
    /// conjunct is implied by the second: a remainder below 0.5 means
    /// Int(heading) is a multiple of 5, one above 4.5 means Int(heading + 1) is.
    private func legacyNearLabeledTick(heading: Float) -> Bool {
        let headingDiv5Remainder = heading.truncatingRemainder(dividingBy: 5)
        return (Int(heading) % 5 == 0 || Int(heading + 1) % 5 == 0) &&
               (headingDiv5Remainder < 0.5 || headingDiv5Remainder > 4.5)
    }

    @Test("The nearest-label clearance test matches the shipped expression over a full turn")
    func nearLabeledTickMatchesLegacyExpression() {
        for tenths in 0..<3600 {
            let heading = Float(tenths) / 10
            #expect(TelemetryTapeLayout.isNearLabeledTick(currentTelemetryValue: heading,
                                                          labelStepUnits: labelStepDegrees,
                                                          clearanceUnits: clearanceDegrees)
                    == legacyNearLabeledTick(heading: heading),
                    "heading \(heading)")
        }
    }

    // MARK: - Speed and altitude tapes (vertical, values increasing upwards)

    @Test("The current value's tick sits on the centre line, and a higher value sits higher, a smaller y")
    func currentValueIsCentredAndHigherValuesSitHigher() {
        #expect(tickY(knots: 150, speed: 150) == centerY)
        // 10 kt above the current speed: 50 pt above the centre
        #expect(tickY(knots: 160, speed: 150) == 450)
        #expect(tickY(knots: 140, speed: 150) == 550)
    }

    @Test("Accelerating slides the ticks down by pointsPerUnit per unit")
    func acceleratingSlidesTicksDown() {
        let yBefore = tickY(knots: 160, speed: 150)
        let yAfterOneKnotFaster = tickY(knots: 160, speed: 151)
        #expect(yAfterOneKnotFaster == yBefore + CGFloat(pointsPerKnot))
    }

    @Test("The vertical window's edges land on the strip's ends: the top is the high value")
    func verticalWindowEdgesLandOnStripEnds() {
        // at 100 kt the ±100 kt window is 0…200 kt: 200 at the top (y = 0), 0 at the bottom (y = 1000)
        #expect(tickY(knots: 200, speed: 100) == 0)
        #expect(tickY(knots: 0, speed: 100) == 1000)
    }

    @Test("Candidate ticks for the altitude tape at rest: −600…600 ft, drawn every 100 ft")
    func altitudeCandidatesAtRest() {
        let candidates = TelemetryTapeLayout.candidateTicks(currentTelemetryValue: 0,
                                                            halfSpanUnits: 500,
                                                            labelStepUnits: 100)
        #expect(candidates == -600...600)
        // the altitude tape's minor step is its label step, so it draws 13 ticks: −600, −500 … 600
        #expect(candidates.filter { $0 % 100 == 0 }.count == 13)
    }

    @Test("Readout rounds to the nearest unit rather than truncating")
    func readoutRoundsToNearestUnit() {
        let cases: [(value: Float, readout: Int)] = [
            (999.6, 1000), (999.4, 999), (17.5, 18), (0.4, 0), (-0.4, 0), (-2.6, -3),
        ]
        for (value, readout) in cases {
            #expect(TelemetryTapeLayout.readout(value) == readout, "value \(value)")
        }
    }

    @Test("Clearance is measured to the nearest label for negative values too")
    func nearLabeledTickForNegativeValues() {
        // labels every 50 kt, 2 kt of clearance; the signed remainder of −25 is −25,
        // which a plain "remainder < clearance" test would have called near
        let cases: [(speed: Float, near: Bool)] = [
            (-0.5, true), (-1.9, true), (-2, false), (-25, false),
            (-48.5, true), (-50, true), (-51.5, true), (-52.5, false),
        ]
        for (speed, near) in cases {
            #expect(TelemetryTapeLayout.isNearLabeledTick(currentTelemetryValue: speed,
                                                          labelStepUnits: labelStepKnots,
                                                          clearanceUnits: clearanceKnots) == near,
                    "speed \(speed)")
        }
    }

    // MARK: - Helpers bound to the suite's strips

    private func tickX(degree: Int, heading: Float) -> CGFloat {
        TelemetryTapeLayout.tickX(candidateTelemetryValue: degree,
                                  currentTelemetryValue: heading,
                                  centerX: centerX,
                                  pointsPerUnit: pointsPerDegree)
    }

    private func tickY(knots: Int, speed: Float) -> CGFloat {
        TelemetryTapeLayout.tickY(candidateTelemetryValue: knots,
                                  currentTelemetryValue: speed,
                                  centerY: centerY,
                                  pointsPerUnit: pointsPerKnot)
    }
}
