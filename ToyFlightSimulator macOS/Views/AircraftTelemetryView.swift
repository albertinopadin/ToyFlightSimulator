//
//  AircraftTelemetryView.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/17/26.
//

import SwiftUI

struct AircraftTelemetryView: View {
    /// @Observable singleton: reading `latestSnapshot` inside `body` is
    /// tracked, so every publish re-renders the panel, including the first
    /// frame after it is toggled on (an onChange-into-@State copy would show
    /// zeros until the next publish, which never comes while paused).
    let aircraftTelemetryStore = AircraftTelemetryStore.sharedInstance

    var viewSize: CGSize

    var body: some View {
        let telemetry = aircraftTelemetryStore.latestSnapshot
        VStack(alignment: .leading, spacing: 6) {
            Label("Aircraft Info", systemImage: "airplane")
                .font(.headline)
                .padding(.bottom, 4)

            Text("Aircraft type: \(telemetry.aircraftType?.rawValue ?? "Undefined")")
            Text("Altitude: \(String(format: "%.0f", telemetry.altitudeInFeet))")
            Text("Speed (knots): \(String(format: "%.0f", telemetry.speedInKnots))")
            Text("Speed (mph): \(String(format: "%.0f", telemetry.speedInMph))")
            Text("Heading: \(String(format: "%.0f", telemetry.heading))")
            Text("Pitch angle: \(String(format: "%.0f", telemetry.pitchAngle))")
            Text("Roll angle: \(String(format: "%.0f", telemetry.rollAngle))")
        }
        .foregroundColor(.white)
        .monospacedDigit()
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 15.0)
                .fill(.black.opacity(0.80))
        )
        .padding(.bottom, 80)
        .padding(.trailing, 10)
        .frame(width: viewSize.width,
               height: viewSize.height,
               alignment: .bottomTrailing)
        .transition(.move(edge: .trailing))
        .zIndex(90)
    }
}

#Preview {
    AircraftTelemetryView(viewSize: CGSize(width: 1920, height: 1080))
}
