# Aircraft Picker Grid with Generated Thumbnails

**Date:** 2026-07-09 (rev 3 — IMPLEMENTED; see "Implementation notes" at the end for what
changed against the plan: OBJ material sanitize, final orientation constants, margin 0.92)
**Status:** Implemented & verified (build ✓, scoped tests ✓, all five thumbnails visually
verified in the X-Plane pose)
**Reference:** `plans/claude/screenshots/xplane_flight_config.png` (X-Plane Flight Configuration screen)

## Goal

Replace the `Picker` at `ToyFlightSimulator macOS/Views/TFSMenu.swift:92` with an X-Plane-style
aircraft picker:

- Vertically growing, scrollable grid, **max 4 aircraft per row**.
- Each card shows the aircraft name and a rendered "photo" of the model in the X-Plane pose:
  **nose pointing right, yawed ~45° toward the viewer, camera slightly above** (~15–20° elevation).
- Selected card highlighted (X-Plane uses a blue fill + white border).
- Photos are **generated from the actual model assets** (OBJ + USDZ) — no hand-made screenshots.
- Generated photos are **cached on disk** so they are not re-rendered on every launch.

```
┌ AIRCRAFT ──────────────────────────────────────────────┐
│ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐        │
│ │F-16     │ │F/A-18   │ │F/A-22   │ │CGTrader │   ▲    │
│ │  ╱▔▔╲➚  │ │  ╱▔▔╲➚  │ │  ╱▔▔╲➚  │ │  ╱▔▔╲➚  │   █    │  ← scrolls when the
│ └─────────┘ └─────────┘ └─────────┘ └─────────┘   │    │    roster outgrows
│ ┌─────────┐                                       ▼    │    the panel
│ │F/A-35   │            (row 2…)                        │
│ └─────────┘                                            │
└────────────────────────────────────────────────────────┘
```

---

## Current State (recon)

- `TFSMenu` is shown as an overlay by `MacGameUIView` when ESC is pressed; **the game is paused
  while the menu is open** (`SceneManager.Paused` toggles with menu visibility) — relevant because
  thumbnail generation while the menu is open competes with almost nothing for the GPU.
- `aircraftType` state lives in `MacGameUIView` (`@State`, default `.f22_cgtrader`) and is passed
  down as a `Binding`. Selection side-effect is `SceneManager.SetPlayerAircraft(aircraftType)` via
  `.onChange` — that behavior must be preserved verbatim.
- `AircraftType` (`GameObjects/AircraftType.swift`) is `String, CaseIterable, Identifiable`; the
  raw values are display names ("F-16 Fighting Falcon", …) — usable directly as card labels.
- Deployment targets, verified in `project.pbxproj` by mapping every target's build
  configurations (target-level settings override project-level): **macOS app 26.0, iOS app 26.0,
  tvOS app 18.0, tests 26.0**. The *project-level* defaults still read macOS 14.0 / iOS 16.0, but
  every target shadows the relevant key, so those values are inert (bumping them would be pure
  tidiness). Consequences for this plan: `LazyVGrid`/`Grid` are trivially available, and
  `@Observable` (Observation framework, macOS 14+/iOS 17+/tvOS 17+) is safe even in Shared code
  compiled for all three targets — the thumbnail store uses it instead of
  `ObservableObject`/Combine (less ceremony, per-property change tracking).
- SceneKit status on the 26 SDKs (worth checking since Apple has been steering 3D work toward
  RealityKit): the installed macOS 26.5 SDK headers carry **no** `API_DEPRECATED` on
  `SCNRenderer`, `snapshotAtTime:withSize:antialiasingMode:`, or `SCNScene` — only long-standing
  legacy members are annotated (OpenGL-era properties in `SCNSceneRenderer.h`,
  `SceneKitDeprecated.h`). Option A builds warning-free against the 26 SDKs.
- The Xcode project uses **filesystem-synchronized groups** (`PBXFileSystemSynchronizedRootGroup`,
  Xcode 16 style) — new `.swift` files dropped into `ToyFlightSimulator Shared/` and
  `ToyFlightSimulator macOS/` are picked up by their targets automatically; no pbxproj surgery.

### Aircraft → asset map (from `ModelLibrary.makeLibrary()` + aircraft class inits)

| `AircraftType` | Class | `ModelType` | Asset file | Engine `basisTransform` | Raw axes (as ModelIO delivers vertices) |
|---|---|---|---|---|---|
| `.f16` | `F16` | `.F16` | `f16r.obj` | `rotate180AroundY` | nose **−Z**, up **+Y** |
| `.f18` | `F18` | `.F18` | `FA-18F.obj` | `rotate180AroundY` | nose **−Z**, up **+Y** |
| `.f22` | `F22` | `.Sketchfab_F22` | `F-22_Raptor.usdz` | `transformYMinusZXToXYZ` | nose **+X**, up **−Z** (det −1, mirrored) |
| `.f22_cgtrader` | `F22_CGTrader` | `.CGTrader_F22` | `cgtrader_F22.usdz` | `transformXMinusZYToXYZ` | nose **−Y**, up **+Z** |
| `.f35` | `F35` | `.Sketchfab_F35` | `F-35A_Lightning_II.usdz` | identity | nose **+Z**, up **+Y** |

How "raw axes" were derived: the engine applies basis transforms row-vector style
(`v_engine = v_raw · B`, per CLAUDE.md), and engine space is nose +Z / up +Y. For an orthonormal
`B`, the raw-space forward is **column 2** of `B`'s 3×3 part and raw up is **column 1**
(`f_raw = (0,0,1)·B⁻¹ = third row of Bᵀ = third column of B`).

All model URLs resolve via `Bundle.main.url(forResource:withExtension:)` — same lookup the
thumbnail generator will use (`ObjModel.swift:13`, `UsdModel.swift:29`).

**Caveat that shapes the design:** the engine reads *flattened mesh vertex buffers*
(`asset.childObjects(of: MDLMesh.self)`) and corrects orientation with `basisTransform`. SceneKit
instead composes the **full USD/OBJ node hierarchy** (including the stage `upAxis` and any root
xform Sketchfab bakes in), so a USDZ that needs a basis transform in the engine may load already
upright in SceneKit (this is why the same files preview upright in Finder/QuickLook). The raw-axes
column is therefore a *seed* for per-aircraft orientation constants, not ground truth — the plan
includes a cheap tuning loop (below) to converge each model in one or two visual passes.

---

## Research: how to generate the photos

Four candidate approaches were researched. **Option A (SceneKit offscreen render) is recommended.**

### Option A — SceneKit `SCNRenderer` offscreen snapshot (recommended)

`SCNRenderer(device:options:)` renders a `SCNScene` **without any view or window**, and
`snapshot(atTime:with:antialiasingMode:)` synchronously produces an image of any pixel size. This
is the standard Apple-platforms way to make 3D file thumbnails with a *controlled* camera; Warren
Moore's gist (references) does exactly this for `.obj/.usd/.usdz` AR QuickLook thumbnails.

- **USDZ**: `SCNScene(url:)` loads USDZ natively with PBR materials — same importer QuickLook uses.
- **OBJ**: `MDLAsset(url:)` → `asset.loadTextures()` → `SCNScene(mdlAsset:)`. The `loadTextures()`
  call is mandatory or materials come in untextured (gotcha called out in Moore's gist). ImageIO
  handles the F-16's `.bmp` and F-18's `.jpg` textures.
- **Camera control**: full — we place an `SCNCamera` node wherever we want (this is the entire
  reason Options C/D lose).
- **Framing**: compute the model's bounding sphere (`SCNNode.boundingSphere`), then
  `distance = radius / sin(min(halfVFov, halfHFov)) × margin`. (Same idea as usdrecord's fallback
  camera, which uses `plane_radius / tan(halfFov) + depth/2` on the bbox — the sphere+sine form is
  rotation-invariant so one formula works for every heading.)
- **Transparent background**: leave `scene.background.contents` unset — snapshot pixels outside
  geometry have alpha 0, letting the SwiftUI card draw its own gradient. (Fallback if a macOS
  version renders opaque black: set the card's background color into the scene background — the
  cards are opaque dark panels in the X-Plane design anyway.)
- **Threading**: `snapshot` is synchronous and callable off the main thread (no view involvement).
  Generation runs on a background actor, serialized one model at a time.
- **Cost**: dominated by asset load (the USDZs are tens of MB); est. 0.1–1 s per aircraft, once
  per cache key, with the game paused. Acceptable.

Why not render with the game engine itself? See Option D — viable, but far more code for a menu
thumbnail; SceneKit gets fidelity "close enough for a 260-pt card" for free. The generator is
isolated behind one function so an engine-based implementation can replace it later without
touching the grid, cache, or store.

### Option B — `usdrecord` (OpenUSD CLI) at build/dev time — rejected for runtime, documented as offline alternative

`usdrecord` renders images of a USD stage via Hydra (same output as usdview). Verified from source
(`pxr/usdImaging/usdAppUtils/frameRecorder.cpp`): when no `--camera` is passed it builds a default
50 mm camera that **frames the stage bbox straight-on from the front** (translate along +Z for
Y-up stages, no azimuth) — so the X-Plane 3/4 pose would require authoring a camera prim per model
(e.g., in a session layer) with hand-computed transforms. Additional blockers:

- Requires a full OpenUSD build **with the imaging stack** (Hydra + `UsdAppUtils`; GPU rendering
  needs a GL context via PySide) — a heavyweight external toolchain to pin in the repo. The
  lightweight `pip install usd-core` wheel historically excludes usdview/usdrecord imaging tools.
- **No OBJ input** — the F-16/F-18 would need an OBJ→USD conversion step first.
- Offline generation also means checked-in images that go stale silently when a model changes —
  the runtime cache keys on the asset file automatically.

It remains a fine option if we ever want CI-generated marketing renders of USD scenes.

### Option C — QuickLook Thumbnailing (`QLThumbnailGenerator`) — rejected

One API call and it handles USDZ… but the camera is **fixed by QuickLook** (~30° up, ~30° around Y
per the Stack Overflow thread in references) with **no control over angle**, and OBJ support is
not guaranteed. Can't produce a consistent X-Plane pose. Rejected.

### Option D — In-engine offscreen Metal pass — deferred (future enhancement)

Load via `Assets.Models[...]` (now lazy, so single-model load is cheap) and encode a one-off
forward pass into an offscreen texture. Pros: pixel-exact material/orientation parity with the
game (basis transforms, winding fixes, sRGB policy all inherited). Cons: needs a dedicated
forward pipeline state + shader (the existing ~37 pipelines are all tied to deferred/OIT pass
structures), a lighting rig, readback, and careful non-interference with the render/update thread
handshake. That's a multi-day change for a menu card. The `AircraftThumbnailGenerating` seam in
the design below exists so this can be swapped in later.

### SwiftUI grid research

- **`LazyVGrid`** (macOS 11+): column layout via `[GridItem]`; items created lazily as they
  scroll in; the standard scrollable-grid container. Exactly 4 per row:
  `Array(repeating: GridItem(.flexible(), spacing: s), count: 4)`. `.flexible()` divides the
  available width evenly (vs `.fixed` hardcoded widths, vs `.adaptive` which fits *as many
  columns as possible* — wrong tool here since we want exactly 4).
- **`Grid`/`GridRow`** (macOS 13+): eager, non-scrolling, great for small static tables. It would
  work for today's 5 aircraft but doesn't scroll by itself and requires manual row chunking.
- **Decision:** `ScrollView(.vertical) { LazyVGrid(columns: 4×flexible) }` — matches "vertically
  growing and scrollable" literally, keeps the 4-per-row invariant as the roster grows, and the
  laziness is free future-proofing. (With 5 items today the perf difference is nil; the semantics
  are what we're buying.)

---

## Design

### The pose (X-Plane framing)

Everything is normalized to one canonical model orientation, then one shared camera:

1. **Per-aircraft uprighting rotation** brings the loaded asset to *nose = +X, up = +Y* in
   SceneKit's right-handed Y-up world.
2. **Shared heading yaw of −45° about Y** swings the nose from +X toward +Z (toward the camera):
   nose points screen-right, rotated 45° out of the screen plane → viewer sees the aircraft's
   front-left quarter, exactly the X-Plane pose.
3. **Camera on the +Z side, elevated ~18°**, looking at the model center:
   `cameraPos = distance × (0, sin 18°, cos 18°)`, `simdLook(at: center)`.
4. **Distance from bounding sphere**: `d = r / sin(min(halfVFov, halfHFov)) × 1.08` with a ~30°
   vertical FOV (longer lens ≈ less perspective distortion, matching X-Plane's look).

Initial uprighting seeds (constants, tuned visually once — see Tuning loop):

| Aircraft | Seed uprighting | Confidence / rationale |
|---|---|---|
| `.f16`, `.f18` (OBJ) | yaw −90° about Y | High — OBJ has no scene transforms; raw nose −Z → −90° yaw lands it on +X |
| `.f35` (Sketchfab USDZ) | yaw +90° about Y | Medium — engine basis is identity (mesh nose +Z); if SceneKit's composed stage matches, +90° lands nose on +X |
| `.f22` (Sketchfab USDZ) | yaw −90° about Y | Low — engine needs a det−1 basis for the raw mesh, but SceneKit composes the USD xform stack; assume upright with nose −Z (usual USDZ front convention), tune if not |
| `.f22_cgtrader` (USDZ) | yaw −90° about Y | Low — Z-up-authored source; SceneKit's upAxis handling should upright it leaving nose −Z; tune if not |

The spec type also carries an optional `extraRotation` quaternion for the low-confidence cases in
case a model needs more than a yaw (e.g., if SceneKit does *not* fully upright a stage, the
raw-axes table above tells us exactly which axis fix to add).

Note on the Sketchfab F-22's mirrored basis (det −1): a mirror can't be expressed as a rotation,
so if SceneKit shows it mirrored relative to the game, the thumbnail's *markings* would be
flipped — invisible at card size. Not worth chasing; noted for honesty.

### Lighting rig

`autoenablesDefaultLighting` is the fallback, but an explicit three-light rig photographs better
and is deterministic:

- **Key**: directional, from upper-front-left of the subject (euler ≈ pitch −40°, yaw −30°).
- **Fill**: directional from the opposite side at ~25% intensity.
- **Ambient**: low, so the belly doesn't go black.

### Caching

- **Disk**: `Caches/<bundle-id>/AircraftThumbnails/<case>-<key16>.png`
  (`FileManager.cachesDirectory` — correct under sandbox or not; OS may purge it, we just regen).
- **Key** = SHA-256 (CryptoKit) over: case name, model file name+ext, **model file size + mtime**
  (content fingerprint without hashing a 50 MB USDZ), all pose/camera constants, pixel size, and
  a global `specVersion` int. Any constant tweak or asset change ⇒ new key ⇒ regenerate; a
  cache-store prunes older files for the same aircraft prefix.
- **In-memory**: published `[AircraftType: CGImage]` on the store (below). No need for `TFSCache`
  here — it's ≤ a handful of images with SwiftUI-observed lifetime.

### Generation lifecycle

- `AircraftThumbnailStore` (`@Observable`, `@MainActor`) owns `thumbnails: [AircraftType: CGImage]`.
- `MacGameUIView` owns it as `@State` (survives menu open/close) and passes it to `TFSMenu`.
- First menu open → grid's `.task` calls `ensureAllThumbnails()`; each aircraft is checked against
  disk (hit: decode + publish, sub-ms) or rendered (miss) on a **background actor** — an actor so
  renders serialize naturally (one SCNRenderer at a time), UI never blocks, and cards fill in as
  images arrive. Cards show a placeholder (airplane glyph + spinner) until then.
- Generating on first menu open (rather than app launch) is deliberate: the game is paused behind
  the menu, so we never compete with engine startup or live rendering. After the first run the
  disk cache makes every subsequent launch instant. (Easy to add a launch-time prewarm later —
  one call site.)

### File layout

```
ToyFlightSimulator Shared/AssetPipeline/Thumbnails/
  AircraftThumbnailSpec.swift        # per-aircraft pose spec + camera config + cache key (pure logic)
  AircraftThumbnailGenerator.swift   # SceneKit scene build + offscreen snapshot
  AircraftThumbnailCache.swift       # disk load/store/prune (ImageIO PNG)
  AircraftThumbnailStore.swift       # @Observable store + background actor orchestration
ToyFlightSimulator macOS/Views/
  AircraftGridPicker.swift           # ScrollView + LazyVGrid + AircraftCard (X-Plane style)
```

Shared files use `#if canImport(AppKit)` only where the snapshot image type differs
(NSImage/UIImage → CGImage); everything else is platform-neutral (SceneKit exists on iOS/tvOS, so
an iOS picker can reuse the whole stack later). Framing math and cache keys are pure static
helpers — unit-testable without Metal, per this repo's Metal-free test convention.

---

## Code

New files are given in full (they *are* the diff); existing files as unified diffs.

### New: `ToyFlightSimulator Shared/AssetPipeline/Thumbnails/AircraftThumbnailSpec.swift`

```swift
//
//  AircraftThumbnailSpec.swift
//  ToyFlightSimulator
//

import Foundation
import CryptoKit
import simd

/// Shared camera/pose constants for the X-Plane style aircraft "photo":
/// nose pointing screen-right, yawed toward the viewer, camera slightly above.
struct ThumbnailCameraConfig {
    /// Bump to invalidate every cached thumbnail after changing framing,
    /// lighting, or per-aircraft orientation constants.
    static let specVersion = 1

    /// Yaw applied after uprighting (nose = +X): negative swings the nose
    /// from +X toward +Z, i.e. toward the camera. X-Plane pose ≈ -45°.
    var headingDegrees: Float = -45
    /// Camera height angle above the horizon.
    var elevationDegrees: Float = 18
    /// Vertical field of view. Longer lens = flatter perspective.
    var verticalFovDegrees: Float = 30
    /// Extra distance factor so wingtips don't kiss the frame edge.
    var framingMargin: Float = 1.08
    /// Output size in pixels (16:10, 2x a ~320pt-wide card).
    var pixelWidth: Int = 1280
    var pixelHeight: Int = 800

    /// Camera distance so a bounding sphere of `radius` fits the frustum in
    /// both axes. Pure math -> unit-testable without Metal/SceneKit.
    func cameraDistance(boundingRadius: Float) -> Float {
        let halfV = verticalFovDegrees.toRadians / 2
        let aspect = Float(pixelWidth) / Float(pixelHeight)
        let halfH = atan(tan(halfV) * aspect)
        let halfMin = min(halfV, halfH)
        return (boundingRadius / sin(halfMin)) * framingMargin
    }
}

/// How to photograph one aircraft: which asset to load and how to rotate it
/// so its nose points +X, upright, in SceneKit's right-handed Y-up world.
/// The generator applies the shared heading/elevation on top.
struct AircraftThumbnailSpec {
    let aircraft: AircraftType
    let modelName: String
    let modelExtension: ModelExtension
    /// Loaded asset -> canonical nose +X / up +Y. Seeded from ModelLibrary's
    /// basis transforms; verify visually and tune (bump specVersion).
    let uprighting: simd_quatf
    /// Escape hatch for assets whose scene graph doesn't upright them.
    let extraRotation: simd_quatf

    init(aircraft: AircraftType,
         modelName: String,
         modelExtension: ModelExtension,
         uprightingYawDegrees: Float,
         extraRotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])) {
        self.aircraft = aircraft
        self.modelName = modelName
        self.modelExtension = modelExtension
        self.uprighting = simd_quatf(angle: uprightingYawDegrees.toRadians, axis: [0, 1, 0])
        self.extraRotation = extraRotation
    }

    var modelURL: URL? {
        Bundle.main.url(forResource: modelName, withExtension: modelExtension.rawValue)
    }

    /// One spec per AircraftType. Model names/extensions mirror
    /// ModelLibrary.makeLibrary() -- keep in sync when aircraft are added.
    static func spec(for aircraft: AircraftType) -> AircraftThumbnailSpec {
        switch aircraft {
            case .f16:
                return .init(aircraft: aircraft, modelName: "f16r", modelExtension: .OBJ,
                             uprightingYawDegrees: -90)   // raw nose -Z
            case .f18:
                return .init(aircraft: aircraft, modelName: "FA-18F", modelExtension: .OBJ,
                             uprightingYawDegrees: -90)   // raw nose -Z
            case .f22:
                return .init(aircraft: aircraft, modelName: "F-22_Raptor", modelExtension: .USDZ,
                             uprightingYawDegrees: -90)   // TUNE: stage-dependent
            case .f22_cgtrader:
                return .init(aircraft: aircraft, modelName: "cgtrader_F22", modelExtension: .USDZ,
                             uprightingYawDegrees: -90)   // TUNE: stage-dependent
            case .f35:
                return .init(aircraft: aircraft, modelName: "F-35A_Lightning_II", modelExtension: .USDZ,
                             uprightingYawDegrees: 90)    // raw nose +Z
        }
    }

    /// Enum case name ("f16"), not the display rawValue -- stable file prefix.
    var caseName: String { String(describing: aircraft) }

    /// Cache key: changes when the pose constants, output size, spec version,
    /// or the model file itself (size + mtime fingerprint) change.
    func cacheKey(config: ThumbnailCameraConfig) -> String {
        var components: [String] = [
            "v\(ThumbnailCameraConfig.specVersion)",
            caseName, modelName, modelExtension.rawValue,
            "\(uprighting.vector)", "\(extraRotation.vector)",
            "\(config.headingDegrees)", "\(config.elevationDegrees)",
            "\(config.verticalFovDegrees)", "\(config.framingMargin)",
            "\(config.pixelWidth)x\(config.pixelHeight)",
        ]
        if let url = modelURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            components.append("\(size)-\(mtime)")
        }
        let digest = SHA256.hash(data: Data(components.joined(separator: "|").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
```

### New: `ToyFlightSimulator Shared/AssetPipeline/Thumbnails/AircraftThumbnailGenerator.swift`

```swift
//
//  AircraftThumbnailGenerator.swift
//  ToyFlightSimulator
//
//  Offscreen SceneKit render of an aircraft model in the X-Plane picker pose.
//  No view/window involved: SCNRenderer draws straight into an image, so this
//  is safe to run on a background thread while the game (paused) owns the
//  MTKView. Seam kept narrow so an in-engine Metal renderer could replace it.
//

import Foundation
import SceneKit
import SceneKit.ModelIO   // SCNScene(mdlAsset:)
import ModelIO

enum AircraftThumbnailError: Error {
    case missingModel(String)
    case snapshotFailed(String)
}

enum AircraftThumbnailGenerator {
    /// Renders one aircraft thumbnail. Synchronous & expensive (asset load
    /// dominates) -- call from a background actor/queue only.
    static func render(spec: AircraftThumbnailSpec,
                       config: ThumbnailCameraConfig = ThumbnailCameraConfig()) throws -> CGImage {
        guard let url = spec.modelURL else {
            throw AircraftThumbnailError.missingModel(spec.modelName)
        }

        // --- Load. USDZ via SceneKit's native importer (best PBR fidelity);
        // OBJ via ModelIO (loadTextures() is mandatory or materials are bare).
        let loaded: SCNScene
        switch spec.modelExtension {
            case .USDZ, .USDC:
                loaded = try SCNScene(url: url, options: nil)
            case .OBJ:
                let asset = MDLAsset(url: url)
                asset.loadTextures()
                loaded = SCNScene(mdlAsset: asset)
        }

        // --- Stage: model under a pivot, posed nose-right toward camera.
        let stage = SCNScene()   // background left unset -> transparent pixels

        let modelNode = SCNNode()
        for child in loaded.rootNode.childNodes {
            modelNode.addChildNode(child)
        }
        let heading = simd_quatf(angle: config.headingDegrees.toRadians, axis: [0, 1, 0])
        modelNode.simdOrientation = heading * spec.uprighting * spec.extraRotation

        let pivot = SCNNode()
        pivot.addChildNode(modelNode)
        stage.rootNode.addChildNode(pivot)

        // Recenter: boundingSphere is in pivot space (includes the child's
        // rotation), so shifting the child by -center puts the sphere at origin.
        let (center, radius) = pivot.boundingSphere
        modelNode.simdPosition -= simd_float3(Float(center.x), Float(center.y), Float(center.z))
        guard radius > 0 else {
            throw AircraftThumbnailError.snapshotFailed("empty bounds for \(spec.modelName)")
        }

        // --- Camera: +Z side, elevated, looking at origin.
        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(config.verticalFovDegrees)
        camera.automaticallyAdjustsZRange = true
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        let elevation = config.elevationDegrees.toRadians
        let distance = config.cameraDistance(boundingRadius: Float(radius))
        cameraNode.simdPosition = distance * simd_float3(0, sin(elevation), cos(elevation))
        cameraNode.simdLook(at: .zero, up: [0, 1, 0], localFront: [0, 0, -1])
        stage.rootNode.addChildNode(cameraNode)

        // --- Three-light rig: key upper-front-left, soft fill, ambient floor.
        stage.rootNode.addChildNode(makeDirectionalLight(intensity: 1400,
                                                         eulerDegrees: (-40, -30)))
        stage.rootNode.addChildNode(makeDirectionalLight(intensity: 350,
                                                         eulerDegrees: (-20, 140)))
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 300
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        stage.rootNode.addChildNode(ambientNode)

        // --- Offscreen snapshot.
        let renderer = SCNRenderer(device: nil, options: nil)   // system default MTLDevice
        renderer.scene = stage
        renderer.pointOfView = cameraNode
        renderer.autoenablesDefaultLighting = false
        let size = CGSize(width: config.pixelWidth, height: config.pixelHeight)
        let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)

        guard let cgImage = cgImage(from: image) else {
            throw AircraftThumbnailError.snapshotFailed(spec.modelName)
        }
        return cgImage
    }

    private static func makeDirectionalLight(intensity: CGFloat,
                                             eulerDegrees: (pitch: Float, yaw: Float)) -> SCNNode {
        let light = SCNLight()
        light.type = .directional
        light.intensity = intensity
        let node = SCNNode()
        node.light = light
        node.simdEulerAngles = simd_float3(eulerDegrees.pitch.toRadians,
                                           eulerDegrees.yaw.toRadians,
                                           0)
        return node
    }

    #if canImport(AppKit)
    private static func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
    #else
    private static func cgImage(from image: UIImage) -> CGImage? {
        image.cgImage
    }
    #endif
}
```

### New: `ToyFlightSimulator Shared/AssetPipeline/Thumbnails/AircraftThumbnailCache.swift`

```swift
//
//  AircraftThumbnailCache.swift
//  ToyFlightSimulator
//
//  PNG disk cache under Caches/<bundle-id>/AircraftThumbnails/. Filenames are
//  "<case>-<key16>.png"; a changed key regenerates and prunes the old file.
//  Caches may be purged by the OS -- that's fine, we just regenerate.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

enum AircraftThumbnailCache {
    static func directory() -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "ToyFlightSimulator",
                                    isDirectory: true)
            .appendingPathComponent("AircraftThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func fileURL(caseName: String, key: String) -> URL? {
        directory()?.appendingPathComponent("\(caseName)-\(key.prefix(16)).png")
    }

    static func load(caseName: String, key: String) -> CGImage? {
        guard let url = fileURL(caseName: caseName, key: key),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Writes the PNG and removes older generations for the same aircraft.
    static func store(_ image: CGImage, caseName: String, key: String) {
        guard let url = fileURL(caseName: caseName, key: key),
              let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                                UTType.png.identifier as CFString,
                                                                1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        pruneStaleFiles(caseName: caseName, keeping: url.lastPathComponent)
    }

    private static func pruneStaleFiles(caseName: String, keeping filename: String) {
        guard let dir = directory(),
              let contents = try? FileManager.default.contentsOfDirectory(at: dir,
                                                                          includingPropertiesForKeys: nil)
        else { return }
        for file in contents
        where file.lastPathComponent.hasPrefix("\(caseName)-")
            && file.lastPathComponent != filename {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
```

### New: `ToyFlightSimulator Shared/AssetPipeline/Thumbnails/AircraftThumbnailStore.swift`

```swift
//
//  AircraftThumbnailStore.swift
//  ToyFlightSimulator
//
//  Main-actor observable state + a background actor that serializes the
//  expensive SceneKit renders (one at a time). @Observable is safe in Shared
//  code: every target meets Observation's floor (macOS 26 / iOS 26 / tvOS 18).
//

import Foundation
import CoreGraphics
import Observation

@Observable @MainActor
final class AircraftThumbnailStore {
    private(set) var thumbnails: [AircraftType: CGImage] = [:]
    @ObservationIgnored private var inFlight: Set<AircraftType> = []
    @ObservationIgnored private let worker = Worker()
    @ObservationIgnored private let config = ThumbnailCameraConfig()

    func ensureAllThumbnails() {
        for aircraft in AircraftType.allCases {
            ensureThumbnail(for: aircraft)
        }
    }

    func ensureThumbnail(for aircraft: AircraftType) {
        guard thumbnails[aircraft] == nil, !inFlight.contains(aircraft) else { return }
        inFlight.insert(aircraft)
        let config = self.config
        Task {
            let image = await worker.thumbnail(for: aircraft, config: config)
            inFlight.remove(aircraft)
            if let image {
                thumbnails[aircraft] = image
            }
        }
    }

    /// Serializes disk-check + render off the main actor.
    private actor Worker {
        func thumbnail(for aircraft: AircraftType,
                       config: ThumbnailCameraConfig) -> CGImage? {
            let spec = AircraftThumbnailSpec.spec(for: aircraft)
            let key = spec.cacheKey(config: config)

            let bypassCache = ProcessInfo.processInfo.environment["TFS_REGEN_THUMBNAILS"] == "1"
            if !bypassCache,
               let cached = AircraftThumbnailCache.load(caseName: spec.caseName, key: key) {
                return cached
            }

            do {
                let image = try AircraftThumbnailGenerator.render(spec: spec, config: config)
                AircraftThumbnailCache.store(image, caseName: spec.caseName, key: key)
                return image
            } catch {
                print("[AircraftThumbnailStore] Failed to render \(spec.modelName): \(error)")
                return nil
            }
        }
    }
}
```

*(Note: `CGImage` crossing actor boundaries is safe in practice — immutable, thread-safe type —
but isn't formally `Sendable`; under the project's current Swift language mode this compiles
warning-free. If the project later moves to Swift 6 strict concurrency, wrap it or mark the
transfer `nonisolated(unsafe)`.)*

### New: `ToyFlightSimulator macOS/Views/AircraftGridPicker.swift`

```swift
//
//  AircraftGridPicker.swift
//  ToyFlightSimulator macOS
//
//  X-Plane style aircraft picker: scrollable vertical grid, max 4 per row,
//  cards with a generated 3/4-view "photo", name top-left, blue selection.
//

import SwiftUI

struct AircraftGridPicker: View {
    @Binding var selection: AircraftType
    // Plain reference: @Observable stores are tracked by SwiftUI via body reads.
    let thumbnailStore: AircraftThumbnailStore

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AIRCRAFT")
                .font(.headline)
                .foregroundStyle(.secondary)

            ScrollView(.vertical) {
                LazyVGrid(columns: Self.columns, spacing: 14) {
                    ForEach(AircraftType.allCases) { aircraft in
                        AircraftCard(aircraft: aircraft,
                                     image: thumbnailStore.thumbnails[aircraft],
                                     isSelected: selection == aircraft)
                            .onTapGesture { selection = aircraft }
                    }
                }
                .padding(2)   // room for the selection stroke
            }
        }
        .task { thumbnailStore.ensureAllThumbnails() }
    }
}

private struct AircraftCard: View {
    let aircraft: AircraftType
    let image: CGImage?
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(aircraft.rawValue)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(.white)

            Group {
                if let image {
                    Image(image, scale: 2, label: Text(aircraft.rawValue))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    ZStack {
                        Image(systemName: "airplane")
                            .font(.system(size: 36))
                            .foregroundStyle(.tertiary)
                        ProgressView()
                            .controlSize(.small)
                            .offset(y: 28)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.55)
                                 : Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : Color.white.opacity(0.15),
                              lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    AircraftGridPicker(selection: .constant(.f22_cgtrader),
                       thumbnailStore: AircraftThumbnailStore())
        .frame(width: 900, height: 420)
        .background(.black)
}
```

### Diff: `ToyFlightSimulator macOS/Views/TFSMenu.swift`

```diff
@@ struct TFSMenu: View {
     @Binding var aircraftType: AircraftType
     @Binding var hudEnabled: Bool
     @Binding var maxAnisotropy: MaxAnisotropy
+    let thumbnailStore: AircraftThumbnailStore

     var viewSize: CGSize
@@ inside GeometryReader VStack, replacing the aircraft Picker (old lines 92-101)
-                        Picker("Aircraft: ", selection: $aircraftType) {
-                            ForEach(AircraftType.allCases) { aircraftType in
-                                Text("\(aircraftType.rawValue)").tag(aircraftType).padding()
-                            }
-                        }
-                        .pickerStyle(.menu)
-                        .frame(maxWidth: geometry.size.width * 0.35)
-                        .onChange(of: aircraftType) {
-                            SceneManager.SetPlayerAircraft(aircraftType)
-                        }
+                        AircraftGridPicker(selection: $aircraftType,
+                                           thumbnailStore: thumbnailStore)
+                            .frame(maxWidth: geometry.size.width * 0.6)
+                            .frame(maxHeight: .infinity, alignment: .top)
+                            .onChange(of: aircraftType) {
+                                SceneManager.SetPlayerAircraft(aircraftType)
+                            }
@@ #Preview
 #Preview {
     TFSMenu(framesPerSecond: Binding<FPS>.constant(.FPS_120),
             rendererType: Binding<RendererType>.constant(.TiledDeferred),
             volume: Binding<Float>.constant(15.0),
             aircraftType: Binding<AircraftType>.constant(.f22),
             hudEnabled: Binding<Bool>.constant(false),
             maxAnisotropy: Binding<MaxAnisotropy>.constant(.x8),
+            thumbnailStore: AircraftThumbnailStore(),
             viewSize: CGSize(width: 1920, height: 1080))
 }
```

Layout note: the grid sits last in the menu's `VStack`, which is pinned to
`geometry.size.height - 10` — `.frame(maxHeight: .infinity)` hands the grid all remaining
vertical space, and the internal `ScrollView` takes over when rows exceed it. The grid is wider
(`0.6 ×` width) than the other controls (`0.35 ×`) because 4 cards need the room.
**Decided in review: 0.6 stays.**

### Diff: `ToyFlightSimulator macOS/Views/MacGameUIView.swift`

```diff
@@ struct MacGameUIView: View {
     @State private var hudEnabled: Bool = false
     @State private var maxAnisotropy: MaxAnisotropy = Preferences.SelectedMaxAnisotropy
+    // Owned here (not in TFSMenu) so thumbnails survive menu close/reopen.
+    // @State (not @StateObject): the store is @Observable.
+    @State private var thumbnailStore = AircraftThumbnailStore()
@@ in body
                 if shouldDisplayMenu {
                     TFSMenu(framesPerSecond: $framesPerSecond,
                             rendererType: $rendererType,
                             volume: $volume,
                             aircraftType: $aircraftType,
                             hudEnabled: $hudEnabled,
                             maxAnisotropy: $maxAnisotropy,
+                            thumbnailStore: thumbnailStore,
                             viewSize: viewSize)
                 }
```

### Project integration

The project uses Xcode 16 filesystem-synchronized groups, so the new files are picked up
automatically once created in the folders above (Shared files → all three targets; the picker view
→ macOS target). No `project.pbxproj` edits expected; verify target membership on first build
(tvOS/iOS compile the Shared thumbnail files fine — SceneKit, CryptoKit, ImageIO all exist there).

---

## Tuning loop (one-time, per model)

The USDZ uprighting yaws are seeds, not gospel. To converge quickly without cache fights:

1. Run with `TFS_REGEN_THUMBNAILS=1` (Xcode scheme env var) — bypasses the disk cache read so
   every menu open re-renders.
2. Open the menu, look at the five cards, adjust the offending `uprightingYawDegrees` /
   `extraRotation` in `AircraftThumbnailSpec.spec(for:)` (the raw-axes table above says which
   axis to fix), rebuild.
3. When all five look right, remove the env var and bump
   `ThumbnailCameraConfig.specVersion` → stale caches on other machines regenerate on their own.

## Testing

Unit (Swift Testing, Metal-free — new `ToyFlightSimulatorTests/AssetPipeline/AircraftThumbnailSpecTests.swift`):
- Every `AircraftType` case has a spec, and spec `caseName`s are unique (guards the roster/spec
  sync when aircraft are added).
- `cameraDistance(boundingRadius:)`: finite, positive, monotonic in radius, respects margin — a
  couple of golden values (e.g., r=1, fov=30°, square aspect ⇒ `1/sin(15°)×1.08 ≈ 4.17`).
- Cache key: stable across calls; changes when pixel size / heading / specVersion change; two
  different aircraft never collide.
- Per this repo's convention, run scoped: `xcodebuild test-without-building
  -only-testing:ToyFlightSimulatorTests/AircraftThumbnailSpecTests …` (unscoped local `test`
  hangs at app-host launch; CI runs the full suite).

Manual (macOS app):
1. Launch, ESC → menu: five cards, placeholders fill in with rendered photos within ~1–2 s.
2. Pose check: every aircraft nose-right, ~45° toward viewer, slightly top-down, filling the
   card without clipping (X-Plane screenshot side-by-side).
3. Click a card → selection highlight moves, aircraft swaps in scene (existing
   `SetPlayerAircraft` deferred-swap path — pause off to confirm).
4. Quit, relaunch, ESC → photos appear instantly (disk cache hit; no render logging).
5. `ls "$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null || echo ~/Library/Caches)"` → verify
   `…/AircraftThumbnails/*.png` files exist, one per aircraft.
6. Bump `specVersion`, relaunch → thumbnails regenerate, old PNGs pruned.
7. Resize window with menu open → grid stays 4-across, cards scale, no horizontal overflow.

## Risks / open questions

- **USDZ orientation seeds are guesses** (two marked Low confidence). Mitigated by the tuning
  loop; worst case is two extra build-look-adjust cycles.
- **SceneKit vs engine material fidelity**: thumbnails won't be pixel-identical to in-game
  rendering (different renderer, no CSM etc.). Acceptable for cards; Option D is the future
  parity path behind the same seam.
- **Sketchfab F-22 mirrored basis (det −1)**: markings may be mirrored in its thumbnail.
  Invisible at card size; noted.
- **Transparent snapshot background**: expected to work (unset scene background ⇒ alpha 0). If a
  macOS version fights this, fallback is baking the card's dark color into `stage.background` —
  cards are opaque in the X-Plane design anyway.
### Decisions locked in review (2026-07-09)

- **Grid width**: `0.6 ×` panel width. ✔
- **Generation trigger**: first menu open (game paused, zero contention); app-launch prewarm
  remains a one-line addition later if the first-open placeholder flash ever bothers.
- **Deployment targets**: verified 26.0 (macOS/iOS apps) at target level — store implemented
  with `@Observable`; stale project-level 14.0/16.0 defaults are shadowed and left alone.

## Future extensions

- iOS/tvOS picker reusing the Shared thumbnail stack (store/generator/cache are already
  cross-platform).
- In-engine Metal thumbnail renderer for exact material parity (Option D) behind the same
  generator seam.
- Hover effects, aircraft metadata on cards (class/engine count), category sections with
  headers like X-Plane's Airliner/General Aviation split.

---

## Implementation notes (2026-07-09, post-implementation)

Everything landed as planned except the following, discovered during the tune/verify loop
(all five thumbnails were rendered via `AircraftThumbnailRenderTests` inside the app host and
visually inspected):

- **ModelIO's OBJ→SceneKit material bridge can make a model invisible.** The F-16 rendered as
  a fully transparent image while the F-18 (same code path) was fine. Bisected by swapping in a
  flat red material (geometry appeared → materials were the poison), then diffing every
  `SCNMaterialProperty` against the F-18's: two slots differed. (1) `transparent.contents`
  arrives as scalar `NSNumber(1)` (from MTL `d 1.0`); under the default `.aOne` transparency
  mode its alpha reads as 0 → opacity 0. (2) `emission` arrives pure white under the bridged
  PBR lighting model → blown out. Neither texture decode (BMPs were fine, alpha 255) nor
  winding/culling was involved. Fix: `sanitizeObjMaterials(in:)` in the generator resets
  `transparent` to opaque white and `emission` to black on the OBJ path only.
- **Final orientation constants** (`AircraftThumbnailSpec.spec(for:)`):
  - `.f16`, `.f18` (OBJ): yaw −90° — seed was correct.
  - `.f22`, `.f35` (Sketchfab USDZ): yaw −90° / +90° — seeds correct; SceneKit uprights these
    stages itself, as predicted.
  - `.f22_cgtrader`: SceneKit does **not** upright this one — the engine-derived raw axes
    (nose −Y, up +Z) were the correct predictor. Final: `extraRotation` = pitch −90° about X
    (nose −Y→+Z, up +Z→+Y), then `uprightingYawDegrees: 90`.
- **Framing margin 1.08 → 0.92** for better card presence; safe below 1.0 because a jet's
  vertical extent is far smaller than its bounding sphere (no clipping observed on any of the
  five). `specVersion` bumped to 2 (also covers the sanitize change, which isn't part of the
  cache key).
- **Verification**: macOS Debug build clean (Swift 6 mode, zero new warnings);
  `AircraftThumbnailSpecTests` (7 logic tests) and `AircraftThumbnailRenderTests` (end-to-end
  render + PNG round-trip for all five aircraft, ~1.1 s total) pass scoped; app launches and
  quits cleanly with the new store wired into `MacGameUIView`/`TFSMenu`. Thumbnails cache to
  `~/Library/Caches/com.tinoml.dev.ToyFlightSimulator/AircraftThumbnails/` and stale
  generations are pruned on store.
- **CI note**: the render suite is guarded by `.enabled(if: MTLCreateSystemDefaultDevice() != nil)`
  and a 1-minute time limit; if it ever proves flaky on the GitHub runner it can be dropped
  without losing the logic coverage.

## References

Links provided with the task:
- SwiftUI grids overview (avanderlee): https://www.avanderlee.com/swiftui/grid-lazyvgrid-lazyhgrid-gridviews/
- Apple `Grid` documentation: https://developer.apple.com/documentation/swiftui/grid
- OpenUSD toolset (usdrecord section): https://openusd.org/release/toolset.html
- usdrecord source: https://github.com/PixarAnimationStudios/OpenUSD/blob/dev/pxr/usdImaging/bin/usdrecord/usdrecord.py

Visited during research:
- OpenUSD `UsdAppUtilsFrameRecorder` (fallback camera = front-view bbox framing; read via GitHub API): https://github.com/PixarAnimationStudios/OpenUSD/blob/dev/pxr/usdImaging/usdAppUtils/frameRecorder.cpp
- Warren Moore — thumbnails of 3D model files via SCNRenderer (incl. `loadTextures()` gotcha): https://gist.github.com/warrenm/f4f1c7f7e71bd88fc3d3df95b60d5f04
- `SCNRenderer` documentation: https://developer.apple.com/documentation/scenekit/scnrenderer
- `SCNRenderer.snapshot(atTime:with:antialiasingMode:)`: https://developer.apple.com/documentation/scenekit/scnrenderer/snapshot(attime:with:antialiasingmode:)
- `SCNSceneRenderer` (pointOfView etc.): https://developer.apple.com/documentation/scenekit/scnscenerenderer
- SceneKit offscreen rendering example (SCNRenderer → MTLTexture): https://github.com/lachlanhurst/SceneKitOffscreenRendering
- QLThumbnailGenerator docs: https://developer.apple.com/documentation/quicklookthumbnailing/qlthumbnailgenerator
- Quick Look Thumbnailing framework: https://developer.apple.com/documentation/quicklookthumbnailing
- QLThumbnailGenerator USDZ camera angle is fixed (Stack Overflow): https://stackoverflow.com/questions/64916927/qlthumbnailgenerator-usdz-angle-of-render
- Getting started with ModelIO (MDLAsset → SceneKit bridging): https://iosdeveloperzone.com/2016/05/10/getting-started-with-modelio/
- Loading an .obj model file (Apple Developer Forums): https://developer.apple.com/forums/thread/3979
- OBJ → SCN with multiple submeshes (Apple Developer Forums): https://developer.apple.com/forums/thread/103245
