//
//  HeadingTapeLayout.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/18/26.
//

import Foundation

/// Pure geometry of a HUD heading tape: a strip of compass ticks that slides
/// under a fixed lubber line as the aircraft turns. Every tick's x is computed
/// from its degree relative to the current heading, so the current heading sits
/// at the centre by construction and there is no scrolling, offset or 360 → 000
/// seam to manage (debugging/claude/heading_tape_centered_no_labels_2026-09-18.md).
///
/// Lives in Shared rather than next to the macOS `HeadingTape` view because the
/// test target compiles the Shared sources itself and cannot link app-only
/// types, and so the iOS HUD can draw the same tape. Metal-free;
/// `HeadingTapeLayoutTests`.
enum HeadingTapeLayout {
    /// Horizontal position of the tick for `degree` when the tape is centred on
    /// `heading`. The current heading's tick sits exactly at `centerX`; a right
    /// turn (heading increasing) moves every tick left.
    static func tickX(degree: Int, heading: Float, centerX: CGFloat, pointsPerDegree: Float) -> CGFloat {
        centerX + (CGFloat(degree) - CGFloat(heading)) * CGFloat(pointsPerDegree)
    }
    
    /// Degrees whose tick can be inside a tape showing ±halfSpanDegrees around
    /// `heading`, widened by one label step per side so a half-visible label at
    /// either edge is still drawn. Runs past 0 and 360 freely; `wrappedLabel`
    /// handles the seam.
    static func candidateDegrees(heading: Float, halfSpanDegrees: Float, labelStepDegrees: Int) -> ClosedRange<Int> {
        let first = Int(floor(heading - halfSpanDegrees)) - labelStepDegrees
        let last = Int(ceil(heading + halfSpanDegrees)) + labelStepDegrees
        return first...last
    }
    
    /// Compass label for a degree that ran past 0 or 360: −10 → 350, 365 → 5.
    static func wrappedLabel(degree: Int) -> Int {
        ((degree % 360) + 360) % 360
    }
    
    /// Nearest whole degree, with 360 shown as 0 so it matches the tape's labels.
    static func readout(heading: Float) -> Int {
        Int(heading.rounded()) % 360
    }
    
    /// True when `heading` (a compass heading in [0, 360)) is within
    /// `clearanceDegrees` of a labeled tick, a multiple of `labelStepDegrees`,
    /// on either side. The remainder alone decides it: a remainder below the
    /// clearance means the tick just passed, one above step − clearance means
    /// the next tick is close.
    static func isNearLabeledTick(heading: Float, labelStepDegrees: Int, clearanceDegrees: Float) -> Bool {
        let degreesPastLabeledTick = heading.truncatingRemainder(dividingBy: Float(labelStepDegrees))
        return degreesPastLabeledTick < clearanceDegrees
            || degreesPastLabeledTick > Float(labelStepDegrees) - clearanceDegrees
    }
}
