# Heading tape: blank labels, centered bar, and heading tracking

**Date:** 2026-09-18 · **Agent:** Codex  
**Status:** Diagnosis verified in a standalone SwiftUI layout probe; fix proposed for owner implementation. Application source files were not changed.

## Diagnosis

There are three separate issues:

1. The parent centers the tape's short frame in the game window.
2. The label row compresses all 360 labels to zero width.
3. The tape does not read aircraft heading or use it to position anything.

The [supplied screenshot](</Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/debugging/screenshots/HeadingTapeBug.png>) shows the first two symptoms: a dark horizontal strip around the middle of the game area, with no visible labels. The Aircraft Info panel at the lower right is visible and reports a heading, so the screenshot also shows that the separate telemetry display is working.

### Why the bar is in the middle

In [MacGameUIView.swift](</Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator macOS/Views/MacGameUIView.swift:31>), the parent is a `ZStack` with its default center alignment. `HeadingTape` enters that stack as a short view: its outer frame is only 80 points tall, at [HeadingTape.swift:32](</Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator macOS/Views/HeadingTape.swift:32>).

The tape's `alignment: .top` aligns content **inside that 80-point frame**. It does not place the frame at the top of the window. The parent still centers the whole frame. Apple documents both the [default stack alignment](https://developer.apple.com/documentation/swiftui/zstack) and the [scope of frame alignment](https://developer.apple.com/documentation/swiftui/view/frame(width:height:alignment:)).

Likewise, `HStack(alignment: .top)` only aligns the labels vertically with one another. `.transition(.move(edge: .top))` describes insertion/removal, and `.zIndex(90)` controls drawing order; neither sets the resting position.

The existing [AircraftTelemetryView.swift](</Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator macOS/Views/AircraftTelemetryView.swift:41>) demonstrates the relevant project pattern: style the small panel first, then wrap it in a frame the size of the game area with the desired alignment.

### Why the numbers disappear

At [HeadingTape.swift:14](</Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator macOS/Views/HeadingTape.swift:14>), `ScrollView` defaults to vertical scrolling. Inside it, an `HStack` contains 360 `Text` views. The row itself is then constrained to `viewSize.width`.

That width describes the entire row's layout space. It does not describe a small window onto a longer row. All the labels and the stack's default spacing must fit into that constrained width. Apple's [layout explanation](https://developer.apple.com/documentation/swiftui/laying-out-a-simple-view) describes how a frame passes a fixed width down to its child and how stacks distribute available space.

I reproduced the tape hierarchy in a temporary `NSHostingView` harness, with a solid green background and geometry measurements on each label. On this machine, running macOS 27.0 and Swift 6.4:

| Probe | Labels measured | Labels with zero width | Label widths |
|---|---:|---:|---|
| Current layout, 1920-point width | 360 | 360 | All 0 points |
| Current layout, 640-point width | 360 | 360 | All 0 points |
| Horizontal scrolling, still constraining the row to 1920 points | 360 | 360 | All 0 points |
| Horizontal scrolling, row width unconstrained | 360 | 0 | 9–25 points |

The captured current-layout image also showed the blank dark bar in the center. Removing the row-width constraint and using horizontal scrolling restored the numbers. These measurements explain the missing labels without assuming a foreground-color or Metal-rendering failure.

**Changing only `ScrollView` to horizontal is insufficient.** The content-width constraint is independently responsible for squeezing the labels. Conversely, keeping a vertical scroll view would not provide the desired horizontal viewport.

The nested heights and padding also need a clear contract: the current content requests 80 points before 15-point padding on every side, while the outside requests 80 points again. Define whether the panel's height includes padding instead of giving both content and panel the same fixed height.

### Why it cannot follow the aircraft yet

`HeadingTape` currently accepts only `viewSize`. Its contents are a static integer range. There is no telemetry read, heading input, scroll-position update, or positional calculation.

The required data path already exists:

- [GameScene.update](</Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Scenes/GameScene.swift:211>) takes a player-aircraft snapshot after the scene update and sends the value to the main actor. Its configured publish interval is `1/60` game seconds; actual delivery follows scene updates and main-actor scheduling.
- [AircraftTelemetryStore](</Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/AircraftTelemetry/AircraftTelemetryStore.swift:10>) is a main-actor `@Observable` store.
- [AircraftTelemetryView.body](</Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator macOS/Views/AircraftTelemetryView.swift:19>) reads `latestSnapshot` directly. Follow that pattern in the tape. Reading an observable property in `body` establishes SwiftUI's [update dependency](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app).

Heading is already measured in degrees, increases toward world +X, and uses world +Z as zero. It represents nose direction, not camera direction or velocity direction. Reuse it rather than reading the aircraft object from the UI thread.

The screenshot's `Heading: 360` is consistent with the information panel rounding a value just below 360 to a whole number. Its `%.0f` formatting can do that even though the stored heading is in `[0, 360)`. This is separate from the blank tape.

## Proposed fix

### Step 1 — Separate the panel from its placement

**Learning objective:** distinguish a view's own dimensions from its placement inside a larger area.

Keep the existing centered root `ZStack`. Give the heading layer its own full-game-size wrapper aligned to the top, following the telemetry panel's pattern. In `MacGameUIView`, pass the current `geometry.size` to this layer so it does not initially receive the `.zero` stored size. No change to the Metal wrapper's sizing is required.

Use this hierarchy, from outside to inside:

```pseudocode
full game-sized transparent frame, aligned top-center
    top margin
        small heading panel, with its own background
            fixed center indicator and current-heading readout
            clipped viewport containing the moving scale
```

Apply the background to the small panel **before** adding the full-height placement frame. Otherwise the background can cover the entire game area. Keep the heading layer below the menu's existing z-index of 100, and disable hit testing on the heading layer because it is a passive display.

Suggested starting dimensions are design choices: 80-point total panel height, 8-point vertical inner padding, 15-point horizontal inner padding, and a 12-point top margin. This leaves 64 points for the panel's actual content. Measure the scale viewport after its horizontal padding; use SwiftUI points, not screenshot pixels or Metal drawable pixels.

For a minimal **static diagnostic repair** to the current code, use a horizontal scroll view, remove the fixed width from its `HStack`, and constrain the viewport instead. Give degree cells equal widths if using their positions as an angular scale; monospaced digits alone do not give `9` and `100` equal-width cells. This repairs visibility but still requires heading-driven positioning and wraparound behavior. For the completed instrument, Step 2 avoids needing an interactive scroll view.

**Completion check:** with a few static labels, the panel remains at the top when the window resizes, its background stays within the panel, and the menu remains above it.

### Step 2 — Position marks relative to the current heading

**Learning objective:** map a circular angle to a horizontal screen coordinate.

A heading tape is a fixed viewport with marks moving underneath a fixed center indicator. A simple implementation can place ticks and labels in a local `ZStack` using explicit positions. It does not need a `ScrollView`, user scrolling, repeated copies of the compass, or a new timer.

Suggested starting scale: show a 90-degree span, with ticks every 5 degrees and numbers every 10 degrees. These are UI design choices, not aircraft specifications. At a 640-point panel width with the proposed horizontal padding, neighboring numeric labels are about 67.778 points apart. At 1920 points, they are 210 points apart. Adjust the span later if the wide-window presentation feels too sparse.

Read the store's latest snapshot inside the heading view's `body`, retaining its fractional heading. For each tick, compute the shortest signed angular difference from the current heading, then convert that difference to points:

```pseudocode
function shortestHeadingDifference(tickHeading_deg, aircraftHeading_deg) -> difference_deg
    difference_deg = tickHeading_deg - aircraftHeading_deg

    while difference_deg < -180
        difference_deg = difference_deg + 360

    while difference_deg >= 180
        difference_deg = difference_deg - 360

    return difference_deg

function makeHeadingMarks(aircraftHeading_deg, viewportWidth_pt) -> marks
    visibleSpan_deg = 90
    tickInterval_deg = 5
    labelInterval_deg = 10
    centerX_pt = viewportWidth_pt / 2
    pointsPerDegree = viewportWidth_pt / visibleSpan_deg
    marks = empty list

    for each tickHeading_deg from 0 through 355, stepping by tickInterval_deg
        difference_deg = shortestHeadingDifference(tickHeading_deg, aircraftHeading_deg)

        // Include one extra tick interval so edge labels can be clipped naturally.
        if absoluteValue(difference_deg) <= visibleSpan_deg / 2 + tickInterval_deg
            tickX_pt = centerX_pt + difference_deg * pointsPerDegree
            isMajorTick = remainder(tickHeading_deg, labelInterval_deg) == 0
            label = empty

            if isMajorTick
                label = tickHeading_deg formatted as three digits

            append mark(id: tickHeading_deg, x_pt: tickX_pt,
                        major: isMajorTick, label: label) to marks

    return marks
```

The viewport's local origin is its left edge; positive X goes right. A positive angular difference places a mark to the right of center. As heading increases during a right turn, the same mark's difference decreases, moving it left. This brings the new heading under the fixed indicator.

Draw each label at its mark's X coordinate, with its natural single-line width. SwiftUI's `position` uses the view's center, which matches this calculation. Put ticks and labels in separate vertical lanes below the readout so they do not overlap. Do not put all the labels back into an `HStack` that must share the viewport width. Clip the moving scale to the viewport; a frame alone does not clip overflowing drawings. See Apple's [clipping documentation](https://developer.apple.com/documentation/swiftui/view/clipped(antialiased:)).

Use canonical tick headings as stable identities, including the `0` tick at north. There are 72 candidate ticks and 36 possible numeric labels; only the nearby marks need views. No optimization beyond this is needed to establish correctness.

**Completion check:** a fixed heading shows the matching direction at center; increasing heading moves marks left; fractional heading changes cause fractional movement.

### Step 3 — Handle north crossing and the readout

**Learning objective:** distinguish circular positioning from rounded text formatting.

At north, the scale should read `... 340 350 000 010 020 ...`. The signed-difference calculation puts 350 left of north and 10 right of it without a special scroll reset.

Use the fractional heading for position. For the fixed numeric readout only:

```pseudocode
displayHeading_deg = remainder(roundToNearestInteger(aircraftHeading_deg), 360)
displayText = displayHeading_deg formatted as three digits
```

For example, 359.6 degrees rounds to `000`. This proposal chooses `000` for north; a `360` convention would also be possible if applied consistently to the display.

Start with direct updates from telemetry. Do not animate the wrapped numeric heading directly: interpolation from 359 to 1 can travel through 180. If smoothing is desired later, interpolate the shortest angular change and then derive tick positions from that intermediate heading. The baseline has no interpolation state to reset on aircraft swaps.

The current telemetry math already holds the last defined heading when the nose is vertical. Preserve that behavior. Before the first snapshot, the store has `aircraftType == nil`; show a placeholder or hide the tape until an aircraft snapshot exists. Read the latest value directly rather than copying it only in an `onChange`, so opening the display while paused can still show the available snapshot.

## Worked example and verification

For a **600-point inner viewport** and a 90-degree span, center X is 300 points and the scale is `600 / 90` points per degree. These values were checked with a scratch Python script:

| Aircraft heading | Tick | Signed difference | Tick X, points |
|---:|---:|---:|---:|
| 0° | 350° | −10° | 233.333 |
| 0° | 0° | 0° | 300.000 |
| 0° | 10° | +10° | 366.667 |
| 359° | 350° | −9° | 240.000 |
| 359° | 0° | +1° | 306.667 |
| 1° | 0° | −1° | 293.333 |
| 90° | 90° | 0° | 300.000 |
| 270° | 270° | 0° | 300.000 |

Across 359° → 1°, the north mark moves 13.333 points left: two degrees of movement, continuously through the center. The angular difference's discontinuity is behind the aircraft, outside this narrow viewport.

**Checks actually executed:**

- Read the working-tree views, the telemetry store, heading calculation, and scene publication path; inspected the supplied screenshot.
- Ran and visually inspected the standalone SwiftUI/AppKit layout probe described above. Verified the vertical default in the installed SwiftUI SDK interface.
- Ran numerical checks for centered headings, fractional headings, north crossing, periodicity after adding a full turn, uniform tick spacing, both viewport edges, panel padding arithmetic, and readout rounding. All passed.
- Temporary diagnostic scripts and renders are under `/private/tmp/heading_tape_analysis/`; they are scratch artifacts, not permanent repository dependencies.

**Checks for the owner after implementation:**

- Preview headings 0°, 90°, 180°, 270°, 359°, and 1° without constructing an aircraft or starting Metal. A small scale subview accepting a heading value is sufficient if deterministic previews are useful.
- Confirm a 640-point-wide window and a larger window both retain readable numbers and top placement.
- Turn both directions through north. Verify the numeric readout and fixed center indicator agree, with no large sweep or empty seam.
- Compare the tape with Aircraft Info during flight; allow for its existing whole-degree rounding. Changing cameras should not change the aircraft heading used by the tape.
- Pause, resize, open the menu, and resume. Confirm the latest heading remains visible, the menu is above the tape, and the tape does not intercept game input.
- Swap aircraft and reset the scene. Confirm the tape follows newly published snapshots without keeping a reference to the old aircraft.

No project build, Xcode tests, or live game validation ran for this diagnosis. The standalone probe validates the current layout failure; the proposed moving instrument still needs implementation and the visual checks above.

## Design sources

- **Apple SwiftUI documentation:** the linked stack, frame, layout, clipping, and Observation references define the framework behavior used in this diagnosis. These are primary API sources.
- **Current codebase:** `AircraftTelemetryView`, `AircraftTelemetryStore`, `GameScene.update`, and `AircraftTelemetry` supply the existing data flow, thread ownership, heading convention, and full-area alignment pattern.
- **This proposal:** the 90-degree viewport, tick/label intervals, panel dimensions, fixed indicator, and explicit signed-angle placement are design choices for this UI. The pseudocode is an engine-specific adaptation of elementary circular-angle arithmetic; no external compass implementation is required.
