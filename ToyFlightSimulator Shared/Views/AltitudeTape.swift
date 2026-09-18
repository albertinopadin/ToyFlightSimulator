//
//  AltitudeTape.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/18/26.
//

import SwiftUI

/// HUD altitude tape pinned to the right edge of the game view: altitude in
/// feet, values increasing upwards, with the readout to the strip's left.
/// This view only chooses the units, the span and the formatting;
/// `VerticalTelemetryTapeView` draws the strip from the geometry in
/// `TelemetryTapeLayout`.
struct AltitudeTape: View {
    /// @Observable singleton: reading `latestSnapshot` inside `body` is tracked,
    /// so every telemetry publish (60 Hz from GameScene.update) redraws the tape.
    let aircraftTelemetryStore = AircraftTelemetryStore.sharedInstance
    let visibleSpanFeet: Float = 5000
    let minorTickStepFeet: Int = 100
    let labelStepFeet: Int = 1000
    /// Room for a five-digit label: the 2-pt labeled tick, the 3-pt gap and
    /// five 14-pt monospaced digits (about 42 pt).
    let tapeWidth: CGFloat = 52
    /// Keeps the strip clear of the heading tape at the top and the telemetry
    /// panel at the bottom. Equal at both ends, so the centre line and the
    /// readout stay at mid-height.
    let topAndBottomInset: CGFloat = 80
    
    var viewSize: CGSize
    
    var body: some View {
        let telemetry = aircraftTelemetryStore.latestSnapshot
        // aircraftType stays nil until the first publish, and for good in a scene
        // without a player aircraft (only FlightboxWithPhysics sets one): draw
        // nothing rather than a confident 0.
        if telemetry.aircraftType != nil {
            // viewSize is .zero on the first body pass, hence the clamp.
            VerticalTelemetryTapeView(tapeLength: max(0, viewSize.height - 2 * topAndBottomInset),
                                      tapeWidth: tapeWidth,
                                      visibleSpanUnits: visibleSpanFeet,
                                      minorTickStep: minorTickStepFeet,
                                      labelStep: labelStepFeet,
                                      currentTelemetryValue: telemetry.altitudeInFeet,
                                      color: .green,
                                      readoutPlacement: .left,
                                      // The scale ends at the runway; below it the ticks stay but no labels.
                                      labelText: { feet in feet >= 0 ? "\(feet)" : "" },
                                      readoutText: { feet in "\(feet)" })
            .frame(width: viewSize.width,
                   height: viewSize.height,
                   alignment: .trailing)
            .transition(.move(edge: .trailing))
            .zIndex(90)
        }
    }
}

#Preview {
    AltitudeTape(viewSize: CGSize(width: 1920, height: 1080))
}
