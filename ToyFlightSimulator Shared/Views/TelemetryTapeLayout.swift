//
//  TelemetryTapeLayout.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/18/26.
//

import Foundation

/// Pure geometry shared by the HUD telemetry tapes: a strip of ticks that
/// slides under a fixed centre line (the lubber line) as the value changes.
/// Every tick's position is computed from its value relative to the current
/// value, so the current value sits at the centre by construction and there
/// is no scrolling, offset or wrap seam to manage
/// (debugging/claude/heading_tape_centered_no_labels_2026-09-18.md).
///
/// Vocabulary: a *value* is the telemetry quantity in the tape's display unit
/// (degrees of heading, feet, knots); a *tick* marks a whole value on the
/// strip; a *step* counts value units between marks. Signs: along a
/// horizontal tape a larger value lies to the right; along a vertical tape a
/// larger value lies higher, which is a SMALLER y because SwiftUI's origin is
/// the top-left corner.
///
/// Lives in Shared rather than next to the platform views because the test
/// target compiles the Shared sources itself and cannot link app-only types,
/// and so the iOS HUD can draw the same tapes. Metal-free;
/// `TelemetryTapeLayoutTests`.
enum TelemetryTapeLayout {
    /// Horizontal position of the tick for `candidateTelemetryValue` on a
    /// tape centred on `currentTelemetryValue`. The current value's tick sits
    /// exactly at `centerX`; as the value rises (a right turn on the heading
    /// tape) every tick moves left.
    static func tickX(candidateTelemetryValue: Int,
                      currentTelemetryValue: Float,
                      centerX: CGFloat,
                      pointsPerUnit: Float) -> CGFloat {
        centerX + (CGFloat(candidateTelemetryValue) - CGFloat(currentTelemetryValue)) * CGFloat(pointsPerUnit)
    }
    
    /// Vertical position of the tick for `candidateTelemetryValue` on a tape
    /// centred on `currentTelemetryValue`, values increasing upwards: a tick
    /// above the current value sits above the centre (a smaller y), and as the
    /// value rises (a climb, an acceleration) every tick moves down.
    static func tickY(candidateTelemetryValue: Int,
                      currentTelemetryValue: Float,
                      centerY: CGFloat,
                      pointsPerUnit: Float) -> CGFloat {
        centerY - (CGFloat(candidateTelemetryValue) - CGFloat(currentTelemetryValue)) * CGFloat(pointsPerUnit)
    }
    
    /// Whole values whose tick can be inside a tape showing ±`halfSpanUnits`
    /// around `currentTelemetryValue`, widened by one label step per side so
    /// a half-visible label at either edge is still drawn. Runs past 0 and 360
    /// freely: `wrappedHeadingLabel` handles the compass seam, and the
    /// vertical tapes blank the labels they do not want (below zero).
    /// Precondition: a finite value (the views draw nothing otherwise, since
    /// `Int(floor(x))` traps on NaN and infinity).
    static func candidateTicks(currentTelemetryValue: Float, halfSpanUnits: Float, labelStepUnits: Int) -> ClosedRange<Int> {
        let first = Int(floor(currentTelemetryValue - halfSpanUnits)) - labelStepUnits
        let last = Int(ceil(currentTelemetryValue + halfSpanUnits)) + labelStepUnits
        return first...last
    }
    
    /// Compass label for a degree that ran past 0 or 360: −10 → 350, 365 → 5.
    static func wrappedHeadingLabel(degree: Int) -> Int {
        ((degree % 360) + 360) % 360
    }
    
    /// Nearest whole unit for the boxed readout at the centre line. Rounded,
    /// not truncated: at 999.6 ft the strip's centre is a hair below the 1000
    /// label, and a readout of 999 would disagree with it. The heading tape
    /// passes the result through `wrappedHeadingLabel` so 359.6° reads 000,
    /// like its labels. Precondition: a finite value (`Int(x.rounded())`
    /// traps on NaN and infinity; the views draw nothing for one).
    static func readout(_ telemetryValue: Float) -> Int {
        Int(telemetryValue.rounded())
    }
    
    /// True when `currentTelemetryValue` is within `clearanceUnits` of a
    /// labeled tick, a multiple of `labelStepUnits`, on either side. The
    /// remainder of the division by the step is the distance past the last
    /// labeled tick, the step minus it is the distance to the next one, and
    /// the smaller of the two is the distance to the nearest label.
    /// `truncatingRemainder` keeps the value's sign, so its magnitude is taken
    /// first: a negative value (sliding backwards, sunk below the runway) is
    /// measured the same way, where comparing the signed remainder against
    /// the clearance would call every negative value near.
    static func isNearLabeledTick(currentTelemetryValue: Float, labelStepUnits: Int, clearanceUnits: Float) -> Bool {
        let step = Float(labelStepUnits)
        let unitsPastLabeledTick = abs(currentTelemetryValue.truncatingRemainder(dividingBy: step))
        let unitsToNearestLabeledTick = min(unitsPastLabeledTick, step - unitsPastLabeledTick)
        return unitsToNearestLabeledTick < clearanceUnits
    }
}
