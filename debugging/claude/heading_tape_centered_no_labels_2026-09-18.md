# Heading tape draws as a blank band mid-screen: an 80-pt frame the ZStack centres, and 360 labels squeezed into the window width

**Date:** 2026-09-18
**Files:** `ToyFlightSimulator macOS/Views/HeadingTape.swift` (new, uncommitted) and the uncommitted
`MacGameUIView.swift` change that adds `HeadingTape(viewSize: viewSize)` to the overlay `ZStack`.
**Status:** Both causes confirmed by rendering the view off-screen with SwiftUI's `ImageRenderer`
(script and images in §4). Fix proposed in §5 and implemented by the owner the same day; the
pre-commit review, its three fixes and the tests are in §6. Checks executed for the diagnosis: the
render script, compiled and run on this machine (Xcode 26 toolchain, macOS 26). Cross-checked
against `debugging/codex/heading_tape_layout_and_tracking_2026-09-18.md`, which reaches the same
diagnosis independently; its two extra suggestions are folded into §5.2 and marked as its.

## 1. Symptom

`debugging/screenshots/HeadingTapeBug.png`, macOS, `FlightboxWithPhysics`, window 3452 × 2084 px
at the 2× Retina scale: 1726 pt wide, about 1012 pt of content below the title bar.

- A dark translucent band spans the full window width at mid-height, from about 470 to 550 pt
  below the top of the content area: about 80 pt tall and centred vertically. No digits in it.
- The band's ends are square although its background is a 15-pt-radius `RoundedRectangle`.
- The Aircraft Info panel (T key) at bottom-right reads Heading 360, so the telemetry path works.
  Nothing in `HeadingTape` reads it yet: the view has no heading input at all.

Expected: a strip at the top centre showing compass labels every 10°, the current heading under
a fixed mark, sliding sideways as the aircraft turns.

## 2. The two SwiftUI layout rules the bug rests on

SwiftUI lays out by **proposal and response**: a parent proposes a size to each child, the child
answers with the size it wants (it may ignore the proposal), and the parent then places the
child inside itself (Apple, WWDC 2022 "Compose custom layouts with SwiftUI"; Eidhof and Kugler,
*Thinking in SwiftUI*, "Layout"). Two consequences:

- **Rule A: a frame's `alignment` places the child inside the frame, not the frame inside its
  parent.** `.frame(width:height:alignment:)` answers with exactly the given size. Apple's
  documentation for the parameter: "Note that most alignment values have no apparent effect when
  the size of the frame happens to match that of this view." A `ZStack` places each child at its
  own centre (its default alignment), so a child whose answer is smaller than the stack ends up
  in the middle.
- **Rule B: a stack shares its proposed width among its children after subtracting the
  spacing.** An `HStack` proposed less width than its spacing needs proposes zero (or less) to
  every child, and a `Text` given zero width draws nothing. Proposed no width limit, the same
  `Text` takes its natural width.

One `ScrollView` rule matters too: its default axis is `.vertical`, and a vertical scroll view
proposes its **own** width (finite) and unlimited height to its content, then sizes itself to the
content's width in that cross axis.

## 3. Root causes

### 3.1 Band in the middle: the outer frame is the tape's own size, so there is nothing to align

Walking the layout from `MacGameUIView`:

1. The `ZStack` proposes the whole window, 1726 × 1012 pt, to `HeadingTape`.
2. `HeadingTape`'s outermost modifier is `.frame(width: viewSize.width, height: 80, alignment: .top)`.
   It answers 1726 × 80.
3. The `ZStack` centres that 1726 × 80 box: top edge at (1012 − 80) / 2 = 466 pt. That is the
   band in the screenshot (render A in §4 lands in the same place).
4. `alignment: .top` places the padded `ScrollView` inside the 80-pt box. The scroll view already
   fills the box, so the alignment moves nothing (rule A).

The sibling overlays avoid this. `GameStats` and `AircraftTelemetryView` end with
`.frame(width: viewSize.width, height: viewSize.height, alignment: .topTrailing)` and
`.bottomTrailing`: a box the size of the **whole window**, so the stack's centring changes
nothing and the frame's own alignment does the placement. `HeadingTape` has the pattern's shape
with `height: 80` where `viewSize.height` belongs.

### 3.2 No numbers: 360 labels squeezed into the window width

The inner `.frame(width: viewSize.width, height: 80, alignment: .top)` proposes 1726 pt to an
`HStack` of 360 `Text` views. Measured by the script (§4):

| Quantity | Value |
|---|---|
| Default `HStack` spacing between two `Text`s (macOS, measured from rendered pixels) | 8 pt |
| Spacing alone, 359 gaps | 2872 pt |
| Natural width of the 360-label row | 10 992 pt, 6.4 × the window |
| Width left for glyphs, 1726 − 2872 | −1146 pt |

The spacing alone is 1.7 × the window width, so every label is proposed zero width and draws
nothing (rule B). The render with the scroll view removed (A2) shows the band and no glyphs at
all; the identical row at its natural width (B2, `HeadingTapeRender_natural_width_band.png`)
shows "0 1 2 3 …". Only the width constraint differs between the two.

### 3.3 The `ScrollView` is the wrong container in three ways

- **Wrong axis.** `ScrollView { … }` scrolls vertically. It proposes its own width, 1696 pt after
  the 15-pt padding, to the row, so the row is squeezed even with the inner frame removed
  (render A4). Only a horizontal scroll view proposes unlimited width.
- **Cross-axis growth is why the ends are square.** The inner frame (1726 pt) is wider than the
  scroll view's own width (1696 pt), and a vertical scroll view sizes itself to its content's
  width, so the padded view becomes 1726 + 30 = 1756 pt: 15 pt past each window edge, which
  pushes the rounded corners off-screen. Render A has square ends; A3, the same view with
  `ScrollView(.horizontal)`, has rounded ends.
- **Wrong tool.** A scroll view moves on user input; nothing in the code moves it with the
  heading. `scrollPosition(id:)` (macOS 14) could drive it, but it would fight scroll semantics
  sixty times a second and has no way to wrap at the 360 → 000 seam.

### 3.4 Modifiers that do nothing today

- `.transition(.move(edge: .top))` only plays when the view is inserted or removed inside
  `withAnimation`. `shouldDisplayHeadingTape` is a constant `true`, so it never plays. Keep it
  only if a toggle key is added, like the T panel's.
- `.padding(15)` sits inside the 80-pt outer frame, so the scroll view gets a 50-pt viewport for
  80-pt content: the inner and outer `height: 80` fight each other. One height, on the strip
  itself, is enough.
- `.zIndex(90)` is fine: `TFSMenu` uses 100 and keeps covering the tape.
- `viewSize` is `.zero` during the first body pass (`MacGameUIView` sets it in `onAppear`), so
  the tape has zero width for one frame. The other overlays share this; harmless.

## 4. Evidence: off-screen renders

`heading_tape_centered_no_labels_render_2026-09-18.swift` (next to this doc) renders
`HeadingTape` verbatim, plus variants, inside a window-sized `ZStack` with `ImageRenderer`, no
app launch. Build and run:

```
swiftc -O -framework SwiftUI heading_tape_centered_no_labels_render_2026-09-18.swift -o /tmp/tape_render
/tmp/tape_render <outDir>
```

| Case | Change from the working copy | Result |
|---|---|---|
| A | none | band centred, full width, square ends, no glyphs: the screenshot (`HeadingTapeRender_current_band.png`) |
| A2 | `ScrollView` removed | band centred, no glyphs: the squeeze alone hides the labels |
| A3 | `ScrollView(.horizontal)`, inner frame kept | rounded ends (the scroll view no longer grows to its content); still centred |
| A4 | inner `frame(width:)` removed, vertical axis kept | square ends (the row grows past the window); still centred |
| S | control: `ScrollView(.horizontal) { Text("SCROLLVIEW CONTENT") }` pinned to the top | band drawn, text NOT drawn (`HeadingTapeRender_scrollview_control_band.png`) |
| B | full-size frame + `.top`, horizontal axis, natural-width row | band at the top; content not drawn, see S |
| B2 | as B, with a clipped natural-width `HStack` instead of the scroll view | band at the top, "0 1 2 3 …" visible (`HeadingTapeRender_natural_width_band.png`) |
| C | proposed Canvas tape (§5.2) at 0°, 45°, 357.5° | strip top-centre, ticks and labels, 360 → 000 wrap correct (`HeadingTapeRender_canvas_000/045/357.png`) |

Limitation found by case S: on macOS, `ImageRenderer` draws a `ScrollView`'s frame and
background but not its content (the scroll view is AppKit-backed, and Apple documents that
`ImageRenderer` skips platform-framework views). So A, A3, A4 and B prove only band geometry;
the label evidence is A2 versus B2, which contain no scroll view and use the same layout
engine as the app. All images in `debugging/screenshots/` are crops of the 2× renders.

Every number in this document was printed by that script.

## 5. Proposed fix

### 5.1 Pin the strip to the top: the sibling-overlay pattern

Existing engine pattern (`GameStats.swift`, `AircraftTelemetryView.swift`). Replace the
outermost frame:

```swift
// was: .frame(width: viewSize.width, height: 80, alignment: .top)
.padding(.top, 10)
.frame(width: viewSize.width, height: viewSize.height, alignment: .top)
```

The frame now answers with the whole window, so the `ZStack` has nothing to centre, and `.top`
pins the padded strip to the top edge. `.top` centres horizontally on its own. Renders B, B2 and
C all use this and all land at the top centre.

### 5.2 Draw the tape from the heading instead of laying out 360 labels

**Terms.**

- **Lubber line**: the fixed mark at the centre of the strip that the current heading sits
  under. The term is from ship compasses; the HUD heading scale uses the same moving-scale,
  fixed-index idea (MIL-STD-1787, "Aircraft Display Symbology").
- **Points per degree**: how many SwiftUI points of strip one degree of heading occupies; the
  strip's scale.
- **Tape window**: the headings visible at once, `heading ± halfSpan`.
- **Wrap-around**: a degree that runs past 0 or 360 is shown as its compass label, so 365 is
  "005" and −10 is "350".

**The problem.** Laying out all 360 labels and sliding the row needs a row wider than six
windows, a seam at 360 → 0, and 360 views re-laid out on every publish.

**The idea** (my design; the moving-scale, fixed-index convention is the standard aircraft one).
On every heading change, draw only the ticks whose degrees fall inside the window, and compute
each tick's x from its degree **relative to the current heading**. The current heading is at the
centre by construction, so there is no scrolling, no offset and no seam. A right turn increases
the heading (`AircraftTelemetry.heading`: 0 is world +Z, 90 is world +X, a right turn increases
it), so every tick moves left.

**The steps.**

1. Fix the geometry once: strip width, visible span, points per degree, tick and label steps.
2. From the heading, list the candidate degrees `floor(heading − halfSpan) − labelStep` …
   `ceil(heading + halfSpan) + labelStep`, one label step past each edge so a half-visible label
   is still drawn.
3. For each candidate on a 5° multiple, compute x and draw a tick, long on 10° multiples with the
   wrapped three-digit label above it, short otherwise.
4. Draw the lubber line at the centre and the numeric readout below it.
5. Clip to the strip's frame, so ticks past the edges are cut.

```pseudocode
// Geometry, fixed when the view is built. Degrees are compass degrees, points are SwiftUI points.
stripWidth_pt = min(600, viewWidth_pt * 0.4)
visibleSpan_deg = 60                                   // ±30° around the current heading
pointsPerDegree_ptPerDeg = stripWidth_pt / visibleSpan_deg
minorTickStep_deg = 5
labelStep_deg = 10

// x of the tick for `degree` when the tape is centred on heading_deg; the current heading's tick is at centerX_pt
function tickX(degree, heading_deg, centerX_pt, pointsPerDegree_ptPerDeg) -> x_pt
    return centerX_pt + (degree - heading_deg) * pointsPerDegree_ptPerDeg

// compass label for a degree that ran past 0 or 360: −10 → 350, 365 → 5
function wrappedLabel(degree) -> label_deg
    return ((degree mod 360) + 360) mod 360             // the second mod turns a negative remainder positive

// degrees whose tick can be inside the window, widened by one label step per side
function candidateDegrees(heading_deg, halfSpan_deg, labelStep_deg) -> firstDegree...lastDegree
    firstDegree = floor(heading_deg - halfSpan_deg) - labelStep_deg
    lastDegree = ceil(heading_deg + halfSpan_deg) + labelStep_deg
    return firstDegree...lastDegree

// nearest whole degree, 360 shown as 000 so it matches the tape's labels
function readout(heading_deg) -> label_deg
    return round(heading_deg) mod 360

function drawTape(canvas, heading_deg)
    centerX_pt = canvas.width_pt / 2
    for each degree in candidateDegrees(heading_deg, visibleSpan_deg / 2, labelStep_deg)
        if degree mod minorTickStep_deg != 0
            continue
        x_pt = tickX(degree, heading_deg, centerX_pt, pointsPerDegree_ptPerDeg)
        isLabeled = (degree mod labelStep_deg == 0)
        tickHeight_pt = 12 if isLabeled else 6
        draw a vertical line at x_pt from the bottom edge up tickHeight_pt      // white, 1 pt
        if isLabeled
            draw text "%03d" of wrappedLabel(degree), centred above the tick    // monospaced digits
    draw a vertical line at centerX_pt, 18 pt tall, in the accent colour       // the lubber line
    draw text "%03d" of readout(heading_deg) in a box below the lubber line
```

Note: written as a filter instead of a skip (`for each degree … where degree mod
minorTickStep_deg == 0`), the test flips from `!=` to `==`; §6 records that slip.

**Worked example** (printed by the script; drawn in `HeadingTapeRender_canvas_357.png`). Strip
600 pt, span ±30°, so 10 pt per degree; heading 357.5°.

| Step | Value |
|---|---|
| candidate degrees | 317 … 398 |
| degree 350 | label "350" at x = 300 + (350 − 357.5) × 10 = 225 pt |
| degree 360 | label "000" at x = 325 pt, 25 pt right of the lubber line |
| degree 370 | label "010" at x = 425 pt |
| readout | round(357.5) mod 360 = 358, shown "358" |
| readout at 359.6° | 360 mod 360 = 0, shown "000" |

**SwiftUI mapping**, in prose so the owner writes it. The strip is a `Canvas` whose closure
receives a `GraphicsContext` and its size; ticks are `Path`s given to
`context.stroke(_:with:lineWidth:)`, labels are `Text` values given to
`context.draw(_:at:anchor:)`; `.frame(width: stripWidth, height: stripHeight)` then `.clipped()`
on the canvas. The readout is a `Text` under it in a `VStack`, styled like the sibling panels
(`.padding`, the 0.80-black `RoundedRectangle` background), and the outermost modifiers are
§5.1. `Canvas` exists since macOS 12; the project targets macOS 14.

**Integration points.**

- Heading source: read `AircraftTelemetryStore.sharedInstance.latestSnapshot.heading` inside
  `body`, exactly as `AircraftTelemetryView` does. Observation re-renders the tape on every
  publish, 60 Hz from `GameScene.update` (`telemetryPublishInterval = 1/60`,
  `GameScene.swift:35`). The view holds no engine object, so aircraft swaps and scene resets
  need nothing.
- Sign check: a right turn increases the heading, so ticks slide left and the readout counts up.
- Put the four functions in a pure helper (say `HeadingTapeLayout` in
  `ToyFlightSimulator Shared/Views/`, so the iOS UI can reuse it) and test them Metal-free in a
  Swift Testing suite: wrap (−10 → 350, 365 → 5, 360 → 0), x at 357.5° for 350/360/370, the
  candidate range crossing 0 and 360, the readout at 359.6°. The script's `HeadingTapeLayout`
  enum is the same four functions in Swift; it exists to make the images, not to be the
  implementation.
- Let pointer input through with `.allowsHitTesting(false)` on the tape (from the Codex note).
  `GameView` takes mouse buttons, drags, moves and the scroll wheel through AppKit responder
  overrides (`Display/GameView.swift:28-78`), and a SwiftUI overlay claims those events wherever
  it is hit-testable, which its background is. Without the modifier a click, drag or scroll over
  the strip never reaches the game. Keyboard input is unaffected: it arrives through `NSEvent`
  local monitors (`GameViewController.swift:35-37`). `GameStats` and `AircraftTelemetryView`
  have the same latent gap over their panels.
- Hide the tape until a snapshot exists: `latestSnapshot.aircraftType == nil` means nothing has
  been published (from the Codex note). That is the first frame, and every scene without a
  player aircraft, since only `FlightboxWithPhysics` sets `playerAircraft` and
  `GameScene.update` publishes only when one is set. Nothing clears the store on
  `TeardownScene`, so after a scene change into such a scene the previous jet's last heading
  would stay on the tape; clearing the store in the teardown is the one-line fix if that ever
  matters.

**Edge cases.**

- 360 → 000: candidate degrees cross 0 and 360 freely; only the label wraps. Nothing special
  happens at the seam (render C at 357.5°).
- Nose vertical: `AircraftTelemetry.make` holds the previous heading while the nose is within
  1e-6 of vertical, so the tape holds too.
- "000" versus "360": `readout` shows north as "000" to match the tape labels; the T panel
  prints `%.0f` of 359.6 as "360". Aviation practice writes north as 360 (runway 36, "heading
  three-six-zero"), which is a one-line change in `readout` and in the label formatting. Pick one
  and use it in the tape, the readout and the T panel.
- Publish cadence: at a 3°/s turn, one 1/60 s publish moves the tape 0.5 pt at 10 pt/°: smooth,
  no interpolation needed.
- Cost: about 13 ticks and 7 labels per redraw, redrawn only when the heading value changes.
- Window resize: `stripWidth` follows `viewSize`, so the strip re-centres and rescales.

**Alternative kept for reference**, closest to the current code: a natural-width `HStack` strip
(render B2 shows the row) offset by `−heading × pointsPerDegree` inside a clipped frame. It works
but needs the strip drawn three times (−360 … 720) to hide the seam and lays out 1080 `Text`s
per publish. Not recommended.

### 5.3 What to check in the app

1. At launch the strip sits at the top centre with digits visible, and the readout matches the
   T panel's heading (the physics scene starts at 360 / 000).
2. Hold a right turn: ticks slide left and the readout counts up. Left turn: the opposite.
3. Fly through north: … 350, 000, 010 … with no jump.
4. Pull to vertical: the tape holds its last heading instead of spinning.
5. Resize the window: the strip re-centres. ESC: the menu still covers it.
6. Press C for the debug camera and move or drag the pointer across the strip: the camera still
   turns, so the strip is not swallowing mouse input.
7. Start a scene without a player aircraft (any scene but `FlightboxWithPhysics`, via
   `Preferences.StartingSceneType`): no tape is drawn.

## 6. Implementation follow-up (2026-09-18)

The owner implemented §5 in `HeadingTape.swift` the same day with different styling: a
full-width strip, a tick every degree, a label every 5°, the readout under the lubber line, and
the lubber line shortened to a stub within 0.5° of a label so it does not cross the digits.

- **First cut: ticks but no labels** (`debugging/screenshots/DegreeTextMissing.png`). The loop
  was `for degree in candidateDegrees where degree % minorTickStep != 0`. The pseudocode's skip
  test kept its `!=` when it moved into a `where` clause, but a `where` names what to keep, so
  only the degrees that are NOT tick multiples survived, and `degree % labelStep == 0` could
  never be true for them. Rendering the owner's Canvas body off-screen gave 56 ticks and 0
  labels as written, 15 ticks and 15 labels with `== 0`. Fixed by the owner.
- **Pre-commit review**: no correctness defect. Three changes applied in the commit:
  `.allowsHitTesting(false)` on the tape, because its strip and readout are hit-testable
  through their backgrounds and took the scroll-wheel zoom, right-drag look and click picking
  that `GameView` reads through its AppKit responder overrides (`AttachedCamera.swift:78-105`
  uses all three every frame); the tape is hidden while `latestSnapshot.aircraftType == nil`,
  which is before the first publish and in every scene without a player aircraft, since only
  `FlightboxWithPhysics` sets one; and the lubber-line clearance test is the remainder
  comparison alone, as `HeadingTapeLayout.isNearLabeledTick`, because the shipped
  expression's first conjunct (`Int(heading) % 5 == 0 || Int(heading + 1) % 5 == 0`) is
  implied by its second.
- **Where the geometry lives**: the owner's implementation kept the helpers as static
  functions on the `HeadingTape` view, and the test bundle could not link them: the test
  target compiles `ToyFlightSimulator Shared/` itself and sets no `BUNDLE_LOADER`, so a symbol
  that exists only in the macOS target is undefined at link time (`Undefined symbols … static
  ToyFlightSimulator.HeadingTape.wrappedLabel`). They moved to the `HeadingTapeLayout` enum in
  `ToyFlightSimulator Shared/Views/`, the §5.2 suggestion, which the iOS HUD can also use.
- **Tests**: `ToyFlightSimulatorTests/Views/HeadingTapeLayoutTests.swift` (Metal-free) pins the wrap
  through north, the readout rounding (359.6 → 0), the worked example at 357.5°, the current
  heading on the lubber line with a right turn sliding ticks left, the candidate range across
  the seam with the window edges on the strip edges, the clearance boundaries, and the
  simplified clearance test's equivalence with the shipped two-part expression over a full turn
  in 0.1° steps. Seven tests, built with `build-for-testing` and run serially with
  `test-without-building -parallel-testing-enabled NO`; all pass.

## 7. References

1. Apple, SwiftUI documentation, `View.frame(width:height:alignment:)`: the `alignment` note
   quoted in §2. Origin of rule A.
2. Apple, WWDC 2022, "Compose custom layouts with SwiftUI": the proposal-and-response protocol
   every container (and `Layout` conformer) follows.
3. Chris Eidhof and Florian Kugler, *Thinking in SwiftUI* (objc.io), chapter "Layout": how
   `HStack` divides its proposed width among children after spacing, and how `Text` responds to a
   proposal. The clearest explanation of rule B.
4. Apple, SwiftUI documentation, `ImageRenderer`: output includes only views SwiftUI renders
   itself, not platform-framework views. Explains case S.
5. MIL-STD-1787 (US DoD, "Aircraft Display Symbology"): the HUD heading scale as a moving tape
   with a fixed index and a digital readout. Convention only; no number here comes from it.
6. Engine: `GameStats.swift` and `AircraftTelemetryView.swift` (full-size frame + alignment),
   `AircraftTelemetry.swift` (heading convention and the vertical-nose hold), `GameScene.swift:35`
   (publish interval), `TFSMenu.swift:80` (zIndex 100).
7. `debugging/codex/heading_tape_layout_and_tracking_2026-09-18.md` (Codex, same date): an
   independent diagnosis of the same bug with the same causes, verified there with an
   `NSHostingView` probe that measured every label at zero width. Source of the hit-testing and
   first-snapshot points in §5.2.

Design origin: §5.1 is the codebase's own pattern; §5.2's drawing scheme is my design on the
standard moving-scale convention; the hit-testing and first-snapshot points are the Codex note's.
