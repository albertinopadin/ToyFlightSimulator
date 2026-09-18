//
//  SpeedTape.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/18/26.
//

import SwiftUI

/// HUD speed tape pinned to the left edge of the game view: forward speed in
/// knots, values increasing upwards, with the readout to the strip's right.
/// This view only chooses the units, the span and the formatting;
/// `VerticalTelemetryTapeView` draws the strip from the geometry in
/// `TelemetryTapeLayout`.
struct SpeedTape: View {
    /// @Observable singleton: reading `latestSnapshot` inside `body` is tracked,
    /// so every telemetry publish (60 Hz from GameScene.update) redraws the tape.
    let aircraftTelemetryStore = AircraftTelemetryStore.sharedInstance
    let visibleSpanKnots: Float = 200
    let minorTickStepKnots: Int = 5
    let labelStepKnots: Int = 50
    let tapeWidth: CGFloat = 40
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
                                      visibleSpanUnits: visibleSpanKnots,
                                      minorTickStep: minorTickStepKnots,
                                      labelStep: labelStepKnots,
                                      currentTelemetryValue: telemetry.speedInKnots,
                                      color: .green,
                                      readoutPlacement: .right,
                                      // The scale ends at zero; sliding backwards keeps the ticks but no labels.
                                      labelText: { knots in knots >= 0 ? "\(knots)" : "" },
                                      readoutText: { knots in "\(knots)" })
            .frame(width: viewSize.width,
                   height: viewSize.height,
                   alignment: .leading)
            .transition(.move(edge: .leading))
            .zIndex(90)
        }
    }
}

#Preview {
    SpeedTape(viewSize: CGSize(width: 1920, height: 1080))
}
