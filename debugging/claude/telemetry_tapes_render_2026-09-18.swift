// Off-screen renders (SwiftUI ImageRenderer, macOS 13+) of the three HUD tapes exactly as
// MacGameUIView hosts them, compiled from the Shared view files themselves with a stub for the
// telemetry store, so a tape change can be checked without launching the app. Written for the
// 2026-09-18 review of the horizontal/vertical tape refactor; the previous script of this kind is
// heading_tape_centered_no_labels_render_2026-09-18.swift (next to this file).
//
// Build & run from the repo root (PNGs land in <outDir>):
//   V="ToyFlightSimulator Shared/Views"
//   swiftc -O -framework SwiftUI -framework AppKit \
//     debugging/claude/telemetry_tapes_render_2026-09-18.swift \
//     "$V/TelemetryTapeLayout.swift" "$V/HorizontalTelemetryTapeView.swift" "$V/VerticalTelemetryTapeView.swift" \
//     "$V/HeadingTape.swift" "$V/SpeedTape.swift" "$V/AltitudeTape.swift" -o /tmp/tape_render
//   /tmp/tape_render <outDir>
//
// Each case writes <case>.png (window-sized, 2x) plus crops of the heading band (<case>_top.png),
// the speed column (<case>_left.png) and the altitude column (<case>_right.png):
//
//   screenshot   the values in debugging/screenshots/SpeedAltTapesV1.png: heading 0, 17.3 kt, 6.4 ft
//   flight       357.5°, 1024.7 kt, 12345.6 ft — four- and five-digit labels, readout rounding
//   edges        4.7° and 999.7 ft (centre line shrinks to its stub beside a label, 999.7 reads 1000),
//                −3.2 kt (ticks continue below zero without labels, readout "-3")
//   small        the 640 × 480 minimum window
//   no_aircraft  aircraftType nil: every tape hidden
//   nan          heading NaN and altitude +inf draw nothing instead of trapping; speed still draws
//
// The stubs below stand in for AircraftTelemetry / AircraftTelemetryStore / AircraftType, which
// live in the engine and would drag Metal in; only the members the tapes read are declared.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum AircraftType: String { case f22_cgtrader }

struct AircraftTelemetry {
    let aircraftType: AircraftType?
    let heading: Float
    let altitudeInFeet: Float
    let speedInKnots: Float
}

final class AircraftTelemetryStore {
    static let sharedInstance = AircraftTelemetryStore()
    var latestSnapshot = AircraftTelemetry(aircraftType: nil, heading: 0, altitudeInFeet: 0, speedInKnots: 0)
}

// Stand-in for MacMetalViewWrapper (ground green) under the overlay ZStack.
struct Host: View {
    let size: CGSize
    var body: some View {
        ZStack {
            Color(red: 0.6, green: 0.8, blue: 0.4)
            HeadingTape(viewSize: size)
            SpeedTape(viewSize: size)
            AltitudeTape(viewSize: size)
        }
        .frame(width: size.width, height: size.height)
    }
}

@MainActor
func save(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("no destination for \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

@MainActor
func render(_ name: String, size: CGSize, in outDir: URL) {
    let renderer = ImageRenderer(content: Host(size: size))
    renderer.scale = 2
    guard let image = renderer.cgImage else { fatalError("no image for \(name)") }
    save(image, to: outDir.appendingPathComponent("\(name).png"))
    // crops at 2x: the heading band, the speed column, the altitude column
    let crops: [(String, CGRect)] = [
        ("top", CGRect(x: 0, y: 0, width: size.width, height: 60)),
        ("left", CGRect(x: 0, y: 0, width: 140, height: size.height)),
        ("right", CGRect(x: size.width - 140, y: 0, width: 140, height: size.height)),
    ]
    for (suffix, rect) in crops {
        let scaled = CGRect(x: rect.minX * 2, y: rect.minY * 2, width: rect.width * 2, height: rect.height * 2)
        if let crop = image.cropping(to: scaled) {
            save(crop, to: outDir.appendingPathComponent("\(name)_\(suffix).png"))
        }
    }
    print("rendered \(name) at \(Int(size.width))x\(Int(size.height)) pt")
}

@main
struct TelemetryTapesRender {
    static func main() {
        MainActor.assumeIsolated {
            let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
            let window = CGSize(width: 1726, height: 1012)   // the screenshot's content size in points
            let cases: [(String, CGSize, AircraftTelemetry)] = [
                ("screenshot", window, AircraftTelemetry(aircraftType: .f22_cgtrader, heading: 0.0, altitudeInFeet: 6.4, speedInKnots: 17.3)),
                ("flight", window, AircraftTelemetry(aircraftType: .f22_cgtrader, heading: 357.5, altitudeInFeet: 12345.6, speedInKnots: 1024.7)),
                ("edges", window, AircraftTelemetry(aircraftType: .f22_cgtrader, heading: 4.7, altitudeInFeet: 999.7, speedInKnots: -3.2)),
                ("small", CGSize(width: 640, height: 480), AircraftTelemetry(aircraftType: .f22_cgtrader, heading: 45, altitudeInFeet: 1500, speedInKnots: 250)),
                ("no_aircraft", window, AircraftTelemetry(aircraftType: nil, heading: 0, altitudeInFeet: 0, speedInKnots: 0)),
                ("nan", window, AircraftTelemetry(aircraftType: .f22_cgtrader, heading: .nan, altitudeInFeet: .infinity, speedInKnots: 100)),
            ]
            for (name, size, snapshot) in cases {
                AircraftTelemetryStore.sharedInstance.latestSnapshot = snapshot
                render(name, size: size, in: outDir)
            }
        }
    }
}
