// Off-screen renders (SwiftUI ImageRenderer, macOS 13+) of HeadingTape.swift as hosted by
// MacGameUIView's ZStack, to reproduce debugging/screenshots/HeadingTapeBug.png without
// launching the app, isolate the two causes, and check the proposed tape.
// Companion to heading_tape_centered_no_labels_2026-09-18.md (next to this file).
//
// Build & run (any directory; PNGs land in <outDir>):
//   swiftc -O -framework SwiftUI heading_tape_centered_no_labels_render_2026-09-18.swift -o /tmp/tape_render
//   /tmp/tape_render <outDir>
//
// Each case is written as <case>.png (window-sized, 2x) plus <case>_band.png, a crop of the
// region where the tape is (or should be).
//
//   A    current      HeadingTape.swift verbatim inside a window-sized ZStack
//   A2   control      same, ScrollView removed (isolates the HStack squeeze)
//   A3   axis-only    ScrollView(.horizontal), inner frame(width:) kept
//   A4   width-only   vertical ScrollView, inner frame(width:) removed
//   S    control      ScrollView(.horizontal) { Text } — does ImageRenderer draw ScrollView content?
//   B    minimal      full-size frame + .top alignment, horizontal ScrollView, natural-width HStack
//   B2   minimal      same, but a clipped natural-width HStack instead of a ScrollView
//   C    canvas       proposed heading-driven Canvas tape at 0, 45, 357.5 degrees
//
// LIMITATION (case S): on macOS, ImageRenderer draws a ScrollView's frame and background but
// not its content (the scroll view is AppKit-backed). So A, A3, A4 and B only show band
// geometry; the label evidence comes from the ScrollView-free cases A2 (squeezed: nothing)
// and B2 (natural width: labels), which share SwiftUI's layout engine with the app.
//
// Measurements printed to stdout: default HStack spacing between two labels (from pixels),
// natural width of the 360-label row, and the tape's worked example.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Window content size from the screenshot: 3452 x 2084 px at 2x = 1726 x 1042 pt,
// minus the title bar.
let windowSize = CGSize(width: 1726, height: 1012)

// Stand-in for MacMetalViewWrapper (the screenshot's ground green).
struct Host<Content: View>: View {
    let size: CGSize
    @ViewBuilder let content: Content
    var body: some View {
        ZStack {
            Color(red: 0.6, green: 0.8, blue: 0.4)
            content
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - A: HeadingTape.swift verbatim (2026-09-18 working copy)

struct HeadingTapeCurrent: View {
    var viewSize: CGSize
    var body: some View {
        ScrollView {
            HStack(alignment: .top) {
                ForEach(0..<360) {
                    Text("\($0)")
                        .foregroundStyle(.white)
                }
            }
            .frame(width: viewSize.width, height: 80, alignment: .top)
        }
        .foregroundColor(.white)
        .monospacedDigit()
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 15.0).fill(.black.opacity(0.80)))
        .frame(width: viewSize.width, height: 80, alignment: .top)
        .transition(.move(edge: .top))
        .zIndex(90)
    }
}

// A2: no ScrollView at all — the HStack squeeze on its own
struct HeadingTapeNoScrollView: View {
    var viewSize: CGSize
    var body: some View {
        HStack(alignment: .top) {
            ForEach(0..<360) {
                Text("\($0)")
                    .foregroundStyle(.white)
            }
        }
        .frame(width: viewSize.width, height: 80, alignment: .top)
        .foregroundColor(.white)
        .monospacedDigit()
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 15.0).fill(.black.opacity(0.80)))
        .frame(width: viewSize.width, height: 80, alignment: .top)
    }
}

// A3: only the scroll axis corrected
struct HeadingTapeAxisOnly: View {
    var viewSize: CGSize
    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top) {
                ForEach(0..<360) {
                    Text("\($0)")
                        .foregroundStyle(.white)
                }
            }
            .frame(width: viewSize.width, height: 80, alignment: .top)
        }
        .foregroundColor(.white)
        .monospacedDigit()
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 15.0).fill(.black.opacity(0.80)))
        .frame(width: viewSize.width, height: 80, alignment: .top)
    }
}

// A4: only the inner width constraint removed (vertical ScrollView kept)
struct HeadingTapeWidthOnly: View {
    var viewSize: CGSize
    var body: some View {
        ScrollView {
            HStack(alignment: .top) {
                ForEach(0..<360) {
                    Text("\($0)")
                        .foregroundStyle(.white)
                }
            }
        }
        .foregroundColor(.white)
        .monospacedDigit()
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 15.0).fill(.black.opacity(0.80)))
        .frame(width: viewSize.width, height: 80, alignment: .top)
    }
}

// S: does ImageRenderer draw the content of a ScrollView on macOS?
struct ScrollViewControl: View {
    var viewSize: CGSize
    var body: some View {
        ScrollView(.horizontal) {
            Text("SCROLLVIEW CONTENT").font(.title).foregroundColor(.white)
        }
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 15.0).fill(.black.opacity(0.80)))
        .padding(.top, 10)
        .frame(width: viewSize.width, height: viewSize.height, alignment: .top)
    }
}

// MARK: - B: minimal fixes of the existing structure

struct HeadingTapeMinimalFix: View {
    var viewSize: CGSize
    var body: some View {
        ScrollView(.horizontal) {                     // scroll axis = tape axis
            HStack(alignment: .top) {
                ForEach(0..<360) {
                    Text("\($0)")
                        .foregroundStyle(.white)
                }
            }                                          // no frame(width:): natural width
        }
        .foregroundColor(.white)
        .monospacedDigit()
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 15.0).fill(.black.opacity(0.80)))
        .padding(.top, 10)
        .frame(width: viewSize.width,
               height: viewSize.height,              // full-size frame, like GameStats /
               alignment: .top)                      // AircraftTelemetryView, pinned to the top
        .transition(.move(edge: .top))
        .zIndex(90)
    }
}

// B2: no ScrollView — natural-width row, clipped to the window
struct HeadingTapeNaturalWidthClipped: View {
    var viewSize: CGSize
    var body: some View {
        HStack(alignment: .top) {
            ForEach(0..<360) {
                Text("\($0)")
                    .foregroundStyle(.white)
            }
        }
        .fixedSize(horizontal: true, vertical: false)          // natural width: no squeeze
        .frame(width: viewSize.width - 30, alignment: .leading) // overflow to the trailing side...
        .clipped()                                              // ...clipped
        .foregroundColor(.white)
        .monospacedDigit()
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 15.0).fill(.black.opacity(0.80)))
        .padding(.top, 10)
        .frame(width: viewSize.width, height: viewSize.height, alignment: .top)
        .zIndex(90)
    }
}

// MARK: - C: proposed heading-driven tape (Canvas)

/// Pure tape geometry (no SwiftUI), so it can be unit-tested Metal-free.
enum HeadingTapeLayout {
    /// Horizontal position of the tick for `degree` when the tape is centered on `heading`.
    /// Both in degrees; the tick for the current heading sits exactly at `centerX`.
    static func tickX(degree: Int, heading: Float, centerX: CGFloat, pointsPerDegree: CGFloat) -> CGFloat {
        centerX + (CGFloat(degree) - CGFloat(heading)) * pointsPerDegree
    }

    /// Compass label for a degree that may have run past 0 or 360: −10 → 350, 365 → 5.
    static func wrappedLabel(degree: Int) -> Int {
        ((degree % 360) + 360) % 360
    }

    /// Degrees whose tick can be inside a tape showing ±halfSpan around `heading`,
    /// widened by one label step so a half-visible label at either edge is still drawn.
    static func candidateDegrees(heading: Float, halfSpan: CGFloat, labelStep: Int) -> ClosedRange<Int> {
        let first = Int((CGFloat(heading) - halfSpan).rounded(.down)) - labelStep
        let last = Int((CGFloat(heading) + halfSpan).rounded(.up)) + labelStep
        return first...last
    }

    /// Readout: nearest whole degree, 360 shown as 000 so it matches the tape labels.
    static func readout(heading: Float) -> Int {
        Int(heading.rounded()) % 360
    }
}

struct HeadingTapeCanvas: View {
    var heading: Float                 // degrees, [0, 360), from AircraftTelemetry.heading
    var viewSize: CGSize

    let visibleDegrees: CGFloat = 60   // ±30° around the current heading
    let stripHeight: CGFloat = 40
    let minorTickStep = 5
    let labelStep = 10
    var stripWidth: CGFloat { min(600, viewSize.width * 0.4) }
    var pointsPerDegree: CGFloat { stripWidth / visibleDegrees }

    var body: some View {
        VStack(spacing: 4) {
            Canvas { context, size in
                let centerX = size.width / 2
                let degrees = HeadingTapeLayout.candidateDegrees(heading: heading,
                                                                 halfSpan: visibleDegrees / 2,
                                                                 labelStep: labelStep)
                for degree in degrees where degree % minorTickStep == 0 {
                    let x = HeadingTapeLayout.tickX(degree: degree, heading: heading,
                                                    centerX: centerX, pointsPerDegree: pointsPerDegree)
                    let isLabeled = degree % labelStep == 0
                    let tickHeight: CGFloat = isLabeled ? 12 : 6
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: size.height))
                    tick.addLine(to: CGPoint(x: x, y: size.height - tickHeight))
                    context.stroke(tick, with: .color(.white), lineWidth: 1)
                    if isLabeled {
                        let label = HeadingTapeLayout.wrappedLabel(degree: degree)
                        let text = Text(String(format: "%03d", label))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                        context.draw(text, at: CGPoint(x: x, y: size.height - tickHeight - 10), anchor: .center)
                    }
                }
                // fixed lubber line: the current heading is always here
                var lubber = Path()
                lubber.move(to: CGPoint(x: centerX, y: size.height))
                lubber.addLine(to: CGPoint(x: centerX, y: size.height - 18))
                context.stroke(lubber, with: .color(.yellow), lineWidth: 2)
            }
            .frame(width: stripWidth, height: stripHeight)
            .clipped()

            Text(String(format: "%03d", HeadingTapeLayout.readout(heading: heading)))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundColor(.yellow)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.yellow, lineWidth: 1))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 15.0).fill(.black.opacity(0.80)))
        .padding(.top, 10)
        .frame(width: viewSize.width, height: viewSize.height, alignment: .top)
        .zIndex(90)
    }
}

// MARK: - Measurements

/// Two labels with red and green backgrounds; the gap between the backgrounds is the
/// HStack's default spacing. Green is byte 1 in both RGBA and BGRA, so the scan needs
/// no byte-order knowledge.
struct TwoLabels: View {
    var body: some View {
        HStack {
            Text("0").background(Color.red)
            Text("1").background(Color.green)
        }
        .background(Color.white)
        .fixedSize()
    }
}

@MainActor
func measureDefaultSpacing() -> CGFloat {
    let renderer = ImageRenderer(content: TwoLabels())
    renderer.scale = 2
    guard let image = renderer.cgImage,
          let data = image.dataProvider?.data,
          let bytes = CFDataGetBytePtr(data) else { fatalError("no spacing image") }
    let bytesPerRow = image.bytesPerRow
    let bytesPerPixel = image.bitsPerPixel / 8
    let row = image.height / 2
    var lastRed = -1
    var firstGreen = -1
    for x in 0..<image.width {
        let pixel = bytes + row * bytesPerRow + x * bytesPerPixel
        let c0 = Int(pixel[0]), c1 = Int(pixel[1]), c2 = Int(pixel[2])
        let isRed = c1 < 100 && ((c0 > 150 && c2 < 100) || (c2 > 150 && c0 < 100))
        let isGreen = c1 > 150 && c0 < 100 && c2 < 100
        if isRed { lastRed = x }
        if isGreen && firstGreen < 0 { firstGreen = x }
    }
    precondition(lastRed >= 0 && firstGreen > lastRed, "did not find both backgrounds")
    return CGFloat(firstGreen - lastRed - 1) / renderer.scale
}

@MainActor
func measureNaturalRowWidth() -> CGFloat {
    let row = HStack(alignment: .top) {
        ForEach(0..<360) { Text("\($0)") }
    }
    .monospacedDigit()
    .fixedSize()
    let renderer = ImageRenderer(content: row)
    renderer.scale = 1
    guard let image = renderer.cgImage else { fatalError("no row image") }
    return CGFloat(image.width)
}

// MARK: - Rendering

@MainActor
func write(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("cannot create \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    print("wrote \(url.lastPathComponent) \(image.width)x\(image.height)")
}

@MainActor
func render<V: View>(_ name: String, bandRect: CGRect, _ view: V, in outDir: URL) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.cgImage else { fatalError("no image for \(name)") }
    write(image, to: outDir.appendingPathComponent("\(name).png"))
    let scaledBand = CGRect(x: bandRect.minX * 2, y: bandRect.minY * 2, width: bandRect.width * 2, height: bandRect.height * 2)
    if let band = image.cropping(to: scaledBand) {
        write(band, to: outDir.appendingPathComponent("\(name)_band.png"))
    }
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

MainActor.assumeIsolated {
    let spacing = measureDefaultSpacing()
    let naturalWidth = measureNaturalRowWidth()
    print("window: \(windowSize.width) x \(windowSize.height) pt")
    print("default HStack spacing between two labels: \(spacing) pt")
    print("spacing alone for 360 labels: 359 x \(spacing) = \(359 * spacing) pt")
    print("natural width of the 360-label row: \(naturalWidth) pt  (\(naturalWidth / windowSize.width)x the window width)")

    // Worked example for the Canvas tape: 600 pt strip, ±30°, heading 357.5°
    let stripWidth: CGFloat = 600, halfSpan: CGFloat = 30, centerX = stripWidth / 2
    let pointsPerDegree = stripWidth / (2 * halfSpan)
    let heading: Float = 357.5
    print("tape: strip \(stripWidth) pt, ±\(halfSpan)°, \(pointsPerDegree) pt/°, heading \(heading)°")
    print("  candidate degrees: \(HeadingTapeLayout.candidateDegrees(heading: heading, halfSpan: halfSpan, labelStep: 10))")
    for degree in [350, 360, 370] {
        let x = HeadingTapeLayout.tickX(degree: degree, heading: heading, centerX: centerX, pointsPerDegree: pointsPerDegree)
        print("  degree \(degree): label \(String(format: "%03d", HeadingTapeLayout.wrappedLabel(degree: degree))) at x = \(x) pt")
    }
    print("  readout: \(String(format: "%03d", HeadingTapeLayout.readout(heading: heading)))")
    print("  readout for 359.6°: \(String(format: "%03d", HeadingTapeLayout.readout(heading: 359.6)))")

    let middleBand = CGRect(x: 0, y: windowSize.height / 2 - 60, width: 700, height: 120)   // left 700 pt of the centered band
    let topBand = CGRect(x: 0, y: 0, width: 700, height: 120)
    let topCenter = CGRect(x: windowSize.width / 2 - 350, y: 0, width: 700, height: 120)

    render("A_current", bandRect: middleBand, Host(size: windowSize) { HeadingTapeCurrent(viewSize: windowSize) }, in: outDir)
    render("A2_no_scrollview", bandRect: middleBand, Host(size: windowSize) { HeadingTapeNoScrollView(viewSize: windowSize) }, in: outDir)
    render("A3_axis_only", bandRect: middleBand, Host(size: windowSize) { HeadingTapeAxisOnly(viewSize: windowSize) }, in: outDir)
    render("A4_width_only", bandRect: middleBand, Host(size: windowSize) { HeadingTapeWidthOnly(viewSize: windowSize) }, in: outDir)
    render("S_scrollview_control", bandRect: topBand, Host(size: windowSize) { ScrollViewControl(viewSize: windowSize) }, in: outDir)
    render("B_minimal_fix", bandRect: topBand, Host(size: windowSize) { HeadingTapeMinimalFix(viewSize: windowSize) }, in: outDir)
    render("B2_natural_width_clipped", bandRect: topBand, Host(size: windowSize) { HeadingTapeNaturalWidthClipped(viewSize: windowSize) }, in: outDir)
    for heading: Float in [0, 45, 357.5] {
        render("C_canvas_\(heading)", bandRect: topCenter,
               Host(size: windowSize) { HeadingTapeCanvas(heading: heading, viewSize: windowSize) }, in: outDir)
    }
}
