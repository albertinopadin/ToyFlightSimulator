//
//  HeadingTapeLayoutTests.swift
//  ToyFlightSimulatorTests
//
//  Metal-free: the heading tape's geometry is a handful of pure static
//  functions on HeadingTapeLayout (Shared/Views), so the wrap at north, the
//  readout rounding, the tick placement and the lubber-line clearance are
//  pinned here without a view, a window or a telemetry store. The numbers are
//  the worked example in
//  debugging/claude/heading_tape_centered_no_labels_2026-09-18.md.
//

import Foundation
import Testing
@testable import ToyFlightSimulator

@Suite("HeadingTapeLayout", .tags(.math))
struct HeadingTapeLayoutTests {
    /// The doc's worked example: a 600-pt strip showing ±30°, so 10 pt per degree.
    private let centerX: CGFloat = 300
    private let pointsPerDegree: Float = 10
    private let labelStepDegrees = 5
    private let clearanceDegrees: Float = 0.5

    @Test("Labels wrap through north in both directions")
    func wrappedLabelWrapsThroughNorth() {
        let cases: [(degree: Int, label: Int)] = [
            (-360, 0), (-10, 350), (-1, 359), (0, 0), (359, 359), (360, 0), (365, 5), (720, 0),
        ]
        for (degree, label) in cases {
            #expect(HeadingTapeLayout.wrappedLabel(degree: degree) == label, "degree \(degree)")
        }
    }

    @Test("Readout rounds to the nearest degree and shows north as 0, like the labels")
    func readoutRoundsAndWraps() {
        let cases: [(heading: Float, readout: Int)] = [
            (0, 0), (0.4, 0), (179.5, 180), (357.5, 358), (359.4, 359), (359.6, 0),
        ]
        for (heading, readout) in cases {
            #expect(HeadingTapeLayout.readout(heading: heading) == readout, "heading \(heading)")
        }
    }

    @Test("Tick placement reproduces the worked example at 357.5°")
    func tickPlacementWorkedExample() {
        let heading: Float = 357.5
        // 300 + (degree − 357.5) × 10; every value is exact in binary floating point
        #expect(HeadingTapeLayout.tickX(degree: 350, heading: heading, centerX: centerX, pointsPerDegree: pointsPerDegree) == 225)
        #expect(HeadingTapeLayout.tickX(degree: 360, heading: heading, centerX: centerX, pointsPerDegree: pointsPerDegree) == 325)
        #expect(HeadingTapeLayout.tickX(degree: 370, heading: heading, centerX: centerX, pointsPerDegree: pointsPerDegree) == 425)
    }

    @Test("The current heading's tick sits on the lubber line, and a right turn slides ticks left")
    func currentHeadingIsCentredAndRightTurnSlidesLeft() {
        #expect(HeadingTapeLayout.tickX(degree: 45, heading: 45, centerX: centerX, pointsPerDegree: pointsPerDegree) == centerX)
        let xBeforeTurn = HeadingTapeLayout.tickX(degree: 50, heading: 45, centerX: centerX, pointsPerDegree: pointsPerDegree)
        let xAfterOneDegreeRight = HeadingTapeLayout.tickX(degree: 50, heading: 46, centerX: centerX, pointsPerDegree: pointsPerDegree)
        #expect(xAfterOneDegreeRight == xBeforeTurn - CGFloat(pointsPerDegree))
    }

    @Test("Candidate degrees cover the visible window plus one label step per side, across the seam")
    func candidateDegreesCoverTheWindow() {
        #expect(HeadingTapeLayout.candidateDegrees(heading: 0, halfSpanDegrees: 30, labelStepDegrees: labelStepDegrees) == -35...35)

        let acrossNorth = HeadingTapeLayout.candidateDegrees(heading: 357.5, halfSpanDegrees: 30, labelStepDegrees: labelStepDegrees)
        #expect(acrossNorth == 322...393)
        // every whole degree inside the window 327.5…387.5 is a candidate
        #expect(acrossNorth.contains(328) && acrossNorth.contains(387))

        // the window's edges land on the strip's edges: at heading 30 the ±30° window is 0…60,
        // which the 600-pt strip maps to x = 0 and x = 600
        #expect(HeadingTapeLayout.tickX(degree: 0, heading: 30, centerX: centerX, pointsPerDegree: pointsPerDegree) == 0)
        #expect(HeadingTapeLayout.tickX(degree: 60, heading: 30, centerX: centerX, pointsPerDegree: pointsPerDegree) == 600)
    }

    @Test("Lubber line clearance: within half a degree of a labeled tick, on either side")
    func nearLabeledTickBoundaries() {
        let cases: [(heading: Float, near: Bool)] = [
            (0, true), (0.3, true), (0.5, false), (2.5, false), (4.5, false),
            (4.7, true), (5.3, true), (5.7, false), (359.4, false), (359.6, true),
        ]
        for (heading, near) in cases {
            #expect(HeadingTapeLayout.isNearLabeledTick(heading: heading,
                                                        labelStepDegrees: labelStepDegrees,
                                                        clearanceDegrees: clearanceDegrees) == near,
                    "heading \(heading)")
        }
    }

    /// The two-part expression the tape shipped with. Its first conjunct is
    /// implied by the second: a remainder below 0.5 means Int(heading) is a
    /// multiple of 5, one above 4.5 means Int(heading + 1) is.
    private func legacyNearLabeledTick(heading: Float) -> Bool {
        let headingDiv5Remainder = heading.truncatingRemainder(dividingBy: 5)
        return (Int(heading) % 5 == 0 || Int(heading + 1) % 5 == 0) &&
               (headingDiv5Remainder < 0.5 || headingDiv5Remainder > 4.5)
    }

    @Test("The remainder-only clearance test matches the shipped expression over a full turn")
    func nearLabeledTickMatchesLegacyExpression() {
        for tenths in 0..<3600 {
            let heading = Float(tenths) / 10
            #expect(HeadingTapeLayout.isNearLabeledTick(heading: heading,
                                                        labelStepDegrees: labelStepDegrees,
                                                        clearanceDegrees: clearanceDegrees)
                    == legacyNearLabeledTick(heading: heading),
                    "heading \(heading)")
        }
    }
}
