//
//  HeadingTape.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/18/26.
//

import SwiftUI

/// HUD heading tape pinned to the top of the game view: a strip of compass
/// ticks that slides under a fixed lubber line as the aircraft turns, with a
/// numeric readout below it. This view only chooses the units, the span and
/// the compass formatting; `HorizontalTelemetryTapeView` draws the strip from
/// the geometry in `TelemetryTapeLayout`.
struct HeadingTape: View {
    /// @Observable singleton: reading `latestSnapshot` inside `body` is tracked,
    /// so every telemetry publish (60 Hz from GameScene.update) redraws the tape.
    let aircraftTelemetryStore = AircraftTelemetryStore.sharedInstance
    let visibleSpanDegrees: Float = 60
    let minorTickStepDegrees: Int = 1
    let labelStepDegrees: Int = 5
    let tapeHeight: CGFloat = 20
    
    var viewSize: CGSize
    
    var body: some View {
        let telemetry = aircraftTelemetryStore.latestSnapshot
        // aircraftType stays nil until the first publish, and for good in a scene
        // without a player aircraft (only FlightboxWithPhysics sets one): draw
        // nothing rather than a confident 000.
        if telemetry.aircraftType != nil {
            HorizontalTelemetryTapeView(tapeLength: viewSize.width * 0.8,
                                        tapeHeight: tapeHeight,
                                        visibleSpanUnits: visibleSpanDegrees,
                                        minorTickStep: minorTickStepDegrees,
                                        labelStep: labelStepDegrees,
                                        currentTelemetryValue: telemetry.heading,
                                        color: .green,
                                        readoutPlacement: .below,
                                        labelText: { degree in
                                            String(format: "%03d", TelemetryTapeLayout.wrappedHeadingLabel(degree: degree))
                                        },
                                        readoutText: { degrees in
                                            String(format: "%03d", TelemetryTapeLayout.wrappedHeadingLabel(degree: degrees))
                                        })
            .frame(width: viewSize.width,
                   height: viewSize.height,
                   alignment: .top)
            .transition(.move(edge: .top))
            .zIndex(90)
        }
    }
}

#Preview {
    HeadingTape(viewSize: CGSize(width: 1920, height: 1080))
}
