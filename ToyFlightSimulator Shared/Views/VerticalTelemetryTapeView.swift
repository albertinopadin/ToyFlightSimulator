//
//  VerticalTelemetryTapeView.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/18/26.
//

import SwiftUI

/// A vertical telemetry tape: a strip of ticks that slides up and down under a
/// fixed centre line as `currentTelemetryValue` changes, with a boxed readout
/// to its left or right. Larger values lie higher, so a rising value slides
/// the ticks down. Draws whatever it is given: the geometry is
/// `TelemetryTapeLayout`, the unit, span and text choices are the caller's
/// (`SpeedTape`, `AltitudeTape`).
struct VerticalTelemetryTapeView: View {
    /// Which long edge of the strip the readout sits against. The ticks and
    /// the centre line grow from that edge, so they point at the readout, and
    /// the labels start just past their tick and read away from it.
    enum ReadoutPlacement {
        case left, right
    }
    
    /// Strip extent along the value axis, points.
    let tapeLength: CGFloat
    let tapeWidth: CGFloat
    /// Value units visible across the whole strip.
    let visibleSpanUnits: Float
    /// Value units between minor ticks and between labeled ticks.
    let minorTickStep: Int
    let labelStep: Int
    let currentTelemetryValue: Float
    let color: Color
    let readoutPlacement: ReadoutPlacement
    /// Text for a labeled tick's value; an empty string draws the tick alone.
    let labelText: (Int) -> String
    /// Text for the boxed readout at the centre line, given the current value
    /// rounded to the nearest whole unit (`TelemetryTapeLayout.readout`).
    let readoutText: (Int) -> String
    
    // Tick, label and centre-line metrics, points.
    let minorTickLength: CGFloat = 6
    /// A labeled tick is a stub: its label takes the space.
    let labeledTickLength: CGFloat = 2
    let labelFontSize: CGFloat = 14
    /// Gap between the end of a labeled tick and the label's near edge.
    let labelGap: CGFloat = 3
    let centerLineLength: CGFloat = 18
    let centerLineStubLength: CGFloat = 4
    /// Half a label's line height at `labelFontSize` (about 17 pt) plus a
    /// margin. Nearer than this to a label the full centre line would run
    /// through the digits, so it shrinks to the stub. In points, so it holds
    /// at any window height; the layout helper takes it in value units.
    let centerLineLabelClearancePoints: CGFloat = 10
    
    var body: some View {
        // Int(floor(x)) and Int(x.rounded()) trap on a NaN or infinite value: a
        // blown-up physics state must not take the HUD down with it. Every
        // conversion, the readout's included, happens behind this guard.
        if currentTelemetryValue.isFinite {
            tape
        }
    }
    
    private var tape: some View {
        let pointsPerUnit = Float(tapeLength) / visibleSpanUnits
        let candidateTicks = TelemetryTapeLayout.candidateTicks(currentTelemetryValue: currentTelemetryValue,
                                                                halfSpanUnits: visibleSpanUnits / 2,
                                                                labelStepUnits: labelStep)
        let nearLabeledTick = TelemetryTapeLayout.isNearLabeledTick(currentTelemetryValue: currentTelemetryValue,
                                                                    labelStepUnits: labelStep,
                                                                    clearanceUnits: Float(centerLineLabelClearancePoints) / pointsPerUnit)
        let readout = readoutBox(readoutText(TelemetryTapeLayout.readout(currentTelemetryValue)))
        return HStack(spacing: 4) {
            if readoutPlacement == .left {
                readout
            }
            
            Canvas { context, size in
                // Ticks grow from the strip edge the readout sits against:
                // rightwards from the left edge (x = 0) for a readout on the
                // left, leftwards from the right edge (x = width) for one on
                // the right. A label is anchored at its near edge so any digit
                // count reads away from the tick.
                let tickEdgeX: CGFloat = readoutPlacement == .left ? 0 : size.width
                let growthDirection: CGFloat = readoutPlacement == .left ? 1 : -1
                let labelAnchor: UnitPoint = readoutPlacement == .left ? .leading : .trailing
                let centerY = size.height / 2
                
                for tickValue in candidateTicks where tickValue % minorTickStep == 0 {
                    let y = TelemetryTapeLayout.tickY(candidateTelemetryValue: tickValue,
                                                      currentTelemetryValue: currentTelemetryValue,
                                                      centerY: centerY,
                                                      pointsPerUnit: pointsPerUnit)
                    let isLabeled = tickValue % labelStep == 0
                    let tickLength = isLabeled ? labeledTickLength : minorTickLength
                    var tick = Path()
                    tick.move(to: CGPoint(x: tickEdgeX, y: y))
                    tick.addLine(to: CGPoint(x: tickEdgeX + growthDirection * tickLength, y: y))
                    context.stroke(tick, with: .color(color), lineWidth: isLabeled ? 2 : 1)
                    
                    if isLabeled {
                        let text = Text(labelText(tickValue))
                            .font(.system(size: labelFontSize, weight: .medium, design: .monospaced))
                            .foregroundStyle(color)
                        context.draw(text,
                                     at: CGPoint(x: tickEdgeX + growthDirection * (tickLength + labelGap), y: y),
                                     anchor: labelAnchor)
                    }
                }
                
                var centerLine = Path()
                centerLine.move(to: CGPoint(x: tickEdgeX, y: centerY))
                let drawnCenterLineLength = nearLabeledTick ? centerLineStubLength : centerLineLength
                centerLine.addLine(to: CGPoint(x: tickEdgeX + growthDirection * drawnCenterLineLength, y: centerY))
                context.stroke(centerLine, with: .color(color), lineWidth: 2)
            }
            .frame(width: tapeWidth, height: tapeLength)
            .clipped()
            .background(Rectangle().fill(.black.opacity(0.35)))
            .mask {
                LinearGradient(colors: [.clear, .green, .green, .clear],
                               startPoint: .top,
                               endPoint: .bottom)
            }
            
            if readoutPlacement == .right {
                readout
            }
        }
        // A passive display. Without this the strip and the readout, both
        // hit-testable through their backgrounds, would take the scroll-wheel
        // zoom, right-drag look and click picking that GameView reads through
        // its AppKit responder overrides; keyboard input arrives through NSEvent
        // monitors and was never affected.
        .allowsHitTesting(false)
    }
    
    private func readoutBox(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold, design: .monospaced))
            .frame(width: 60, alignment: .trailing)
            .foregroundStyle(color)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color, lineWidth: 1))
            .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.50)))
    }
}
