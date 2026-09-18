//
//  HeadingTape.swift
//  ToyFlightSimulator macOS
//
//  Created by Albertino Padin on 9/18/26.
//

import SwiftUI

/// HUD heading tape pinned to the top of the game view: a strip of compass ticks
/// that slides under a fixed lubber line as the aircraft turns, with a numeric
/// readout below it. The geometry (tick placement, label wrap, readout, lubber
/// clearance) is `HeadingTapeLayout` in Shared; this view only draws it.
struct HeadingTape: View {
    /// @Observable singleton: reading `latestSnapshot` inside `body` is tracked,
    /// so every telemetry publish (60 Hz from GameScene.update) redraws the tape.
    let aircraftTelemetryStore = AircraftTelemetryStore.sharedInstance
    let visibleSpanDegrees: Float = 60
    let minorTickStep: Int = 1
    let labelStep: Int = 5
    let tapeHeight: CGFloat = 20
    /// Within this many degrees of a labeled tick the full-height lubber line
    /// would run through the digits, so it shrinks to a stub.
    let lubberLineLabelClearanceDegrees: Float = 0.5
    
    var viewSize: CGSize
    
    var body: some View {
        let telemetry = aircraftTelemetryStore.latestSnapshot
        // aircraftType stays nil until the first publish, and for good in a scene
        // without a player aircraft (only FlightboxWithPhysics sets one): draw
        // nothing rather than a confident 000.
        if telemetry.aircraftType != nil {
            tape(heading: telemetry.heading)
        }
    }
    
    private func tape(heading: Float) -> some View {
        let stripWidthInPoints: CGFloat = viewSize.width
        let pointsPerDegree = Float(stripWidthInPoints) / visibleSpanDegrees
        let candidateDegrees = HeadingTapeLayout.candidateDegrees(heading: heading,
                                                                  halfSpanDegrees: visibleSpanDegrees / 2,
                                                                  labelStepDegrees: labelStep)
        return VStack(spacing: 4) {
            Canvas { context, size in
                let centerX = size.width / 2
                for degree in candidateDegrees {
                    if degree % minorTickStep != 0 { continue }
                    let x = HeadingTapeLayout.tickX(degree: degree,
                                                    heading: heading,
                                                    centerX: centerX,
                                                    pointsPerDegree: pointsPerDegree)
                    let isLabeled = degree % labelStep == 0
                    let tickHeight: CGFloat = isLabeled ? 2 : 6
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: size.height))
                    tick.addLine(to: CGPoint(x: x, y: size.height - tickHeight))
                    let tickLineWidth: CGFloat = isLabeled ? 2 : 1
                    context.stroke(tick, with: .color(.green), lineWidth: tickLineWidth)
                    if isLabeled {
                        let label = HeadingTapeLayout.wrappedLabel(degree: degree)
                        let text = Text(String(format: "%03d", label))
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(.green)
                        context.draw(text, at: CGPoint(x: x, y: size.height - tickHeight - 10), anchor: .center)
                    }
                }
                
                var lubberLine = Path()
                lubberLine.move(to: CGPoint(x: centerX, y: size.height))
                let nearLabeledTick = HeadingTapeLayout.isNearLabeledTick(heading: heading,
                                                                          labelStepDegrees: labelStep,
                                                                          clearanceDegrees: lubberLineLabelClearanceDegrees)
                let lubberLineHeight: CGFloat = nearLabeledTick ? 4 : 18
                lubberLine.addLine(to: CGPoint(x: centerX, y: size.height - lubberLineHeight))
                context.stroke(lubberLine, with: .color(.green), lineWidth: 2)
            }
            .frame(width: stripWidthInPoints, height: tapeHeight)
            .clipped()
            .background(Rectangle().fill(.black.opacity(0.50)))
            
            Text(String(format: "%03d", HeadingTapeLayout.readout(heading: heading)))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(.green)
                .padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.green, lineWidth: 1))
                .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.50)))
        }
        .frame(width: viewSize.width,
               height: viewSize.height,
               alignment: .top)
        .transition(.move(edge: .top))
        .zIndex(90)
        // A passive display. Without this the strip and the readout, both
        // hit-testable through their backgrounds, would take the scroll-wheel
        // zoom, right-drag look and click picking that GameView reads through
        // its AppKit responder overrides; keyboard input arrives through NSEvent
        // monitors and was never affected.
        .allowsHitTesting(false)
    }
}

#Preview {
    HeadingTape(viewSize: CGSize(width: 1920, height: 1080))
}
