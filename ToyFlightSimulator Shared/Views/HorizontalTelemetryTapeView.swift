//
//  HorizontalTelemetryTapeView.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/18/26.
//

import SwiftUI

/// A horizontal telemetry tape: a strip of ticks that slides sideways under a
/// fixed centre line (the lubber line) as `currentTelemetryValue` changes,
/// with a boxed readout above or below it. Larger values lie to the right, so
/// a rising value slides the ticks left. Draws whatever it is given: the
/// geometry is `TelemetryTapeLayout`, the unit, span and text choices are the
/// caller's (`HeadingTape`).
struct HorizontalTelemetryTapeView: View {
    /// Which long edge of the strip the readout sits against. The ticks and
    /// the centre line grow from that edge, so they point at the readout.
    enum ReadoutPlacement {
        case above, below
    }
    
    /// Strip extent along the value axis, points.
    let tapeLength: CGFloat
    let tapeHeight: CGFloat
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
    /// A label's centre sits this far past the end of its tick.
    let labelOffset: CGFloat = 10
    let centerLineLength: CGFloat = 18
    let centerLineStubLength: CGFloat = 4
    /// Half a three-digit label's width at `labelFontSize` (three 0.6-em
    /// monospaced digits, about 25 pt) plus a margin. Nearer than this to a
    /// label the full centre line would run through the digits, so it
    /// shrinks to the stub. In points, so it holds at any window width; the
    /// layout helper takes it in value units.
    let centerLineLabelClearancePoints: CGFloat = 15
    
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
        return VStack(spacing: 4) {
            if readoutPlacement == .above {
                readout
            }
            
            Canvas { context, size in
                // Ticks grow from the strip edge the readout sits against: up
                // from the bottom edge (y = height) for a readout below, down
                // from the top edge (y = 0) for one above.
                let tickEdgeY: CGFloat = readoutPlacement == .below ? size.height : 0
                let growthDirection: CGFloat = readoutPlacement == .below ? -1 : 1
                let centerX = size.width / 2
                
                for tickValue in candidateTicks where tickValue % minorTickStep == 0 {
                    let x = TelemetryTapeLayout.tickX(candidateTelemetryValue: tickValue,
                                                      currentTelemetryValue: currentTelemetryValue,
                                                      centerX: centerX,
                                                      pointsPerUnit: pointsPerUnit)
                    let isLabeled = tickValue % labelStep == 0
                    let tickLength = isLabeled ? labeledTickLength : minorTickLength
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: tickEdgeY))
                    tick.addLine(to: CGPoint(x: x, y: tickEdgeY + growthDirection * tickLength))
                    context.stroke(tick, with: .color(color), lineWidth: isLabeled ? 2 : 1)
                    
                    if isLabeled {
                        let text = Text(labelText(tickValue))
                            .font(.system(size: labelFontSize, weight: .medium, design: .monospaced))
                            .foregroundStyle(color)
                        context.draw(text,
                                     at: CGPoint(x: x, y: tickEdgeY + growthDirection * (tickLength + labelOffset)),
                                     anchor: .center)
                    }
                }
                
                var centerLine = Path()
                centerLine.move(to: CGPoint(x: centerX, y: tickEdgeY))
                let drawnCenterLineLength = nearLabeledTick ? centerLineStubLength : centerLineLength
                centerLine.addLine(to: CGPoint(x: centerX, y: tickEdgeY + growthDirection * drawnCenterLineLength))
                context.stroke(centerLine, with: .color(color), lineWidth: 2)
            }
            .frame(width: tapeLength, height: tapeHeight)
            .clipped()
            .background(Rectangle().fill(.black.opacity(0.35)))
            .mask {
                LinearGradient(colors: [.clear, .green, .green, .clear],
                               startPoint: .leading,
                               endPoint: .trailing)
            }
            
            if readoutPlacement == .below {
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
            .foregroundStyle(color)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color, lineWidth: 1))
            .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.50)))
    }
}
