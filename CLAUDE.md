# CLAUDE.md

Guidance for Claude Code working with this Metal-based flight simulator for macOS/iOS/tvOS.

The working agreement below is imported from `AGENT_PROJECT_RULES.md` (shared by Claude, Codex, and
Gemini): project purpose, the research / plan / owner-implements / review workflow, explanation and
naming rules, references, and the simple-then-optimized rule. Follow it before anything else in this
file. Research docs start from `research/RESEARCH_TEMPLATE.md`; plans start from
`plans/PLAN_TEMPLATE.md`, which also defines the pseudocode style; reviews start from
`code_reviews/REVIEW_TEMPLATE.md`. The `tfs-research`, `tfs-plan`, and `tfs-review` skills run
those three stages.

@AGENT_PROJECT_RULES.md

## Build Commands

```bash
# macOS Debug
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# macOS Release
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Release CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# macOS Tests
xcodebuild test -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# iOS Simulator
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator iOS" -sdk iphonesimulator -configuration Debug
```

## Project Layout

Three platform targets (`ToyFlightSimulator macOS/`, `ToyFlightSimulator iOS/`, `ToyFlightSimulator tvOS/`)
over a shared engine in `ToyFlightSimulator Shared/`, with tests in `ToyFlightSimulatorTests/`. Browse the
tree for specifics; two conventions aren't visible from it:

- `Math/`: `Transform.*` is canonical — `Math`/`MathUtils` hold niche helpers only.
- `code_reviews/ debugging/ plans/ research/`: agent-authored review, debugging, plan, and research docs
  (`research/` is primarily deep web research done when implementing new systems or features). Each has a
  `claude/` subdir (some also `codex/`/`gemini/`); `debugging/screenshots/` holds visual artifacts.

## Architecture

### Scene Graph
- **Node**: Base class with transform hierarchy (position, rotation, scale). `modelMatrix = parentModelMatrix * localMatrix`, both lazily cached: setters only flag dirty (no eager T·R·S rebuild), the getter rebuilds local + composed world on first read and bumps `worldMatrixGeneration` (derived consumers like `Camera.viewMatrix` compare generations instead of recomputing). `update()` computes the world matrix once for all children. `getRotationEulers()` returns all three angles from one decomposition. Children updated recursively via `update()` → `doUpdate()`.
- **GameObject**: Extends Node. Has `Model` (meshes + materials), `ModelConstants` (shader uniforms), and an optional `rigidBody: RigidBody?` for physics (composition — GameObject no longer implements `PhysicsEntity` itself). `Hashable` for collection use. `objectType: GameObjectType` declares which SceneManager collection it batches into (base class derives Tessellatable / opaque-vs-transparent automatically; subclasses in side collections override — SkyBox/SkySphere → `.sky`, Camera → `.none`, etc.). `registeredObjectType` is the marker SceneManager sets at registration and consumes at unregistration. Runtime despawns (weapons reaping themselves) must call `removeFromScene()` — a bare `parent?.removeChild(self)` leaves the object registered, so it keeps being drawn at its last position and never deallocates.
- **GameScene**: Root node. `buildScene()` overridden by subclasses. `addChild()` auto-registers with SceneManager. Has `addCamera()`, `addLight()` helpers. Holds `playerAircraft: Aircraft?` and a `setPlayerAircraft(_:)` override point for scenes that support runtime aircraft swapping.

### Scenes (Scenes/)
`GameScene` base class provides `addGround(color:restitution:rotationZ:scale:) -> (Quad, PlaneRigidBody)` and `setupDefaultSky()` helpers (OIT → SkySphere, SinglePassDeferred → SkyBox) so subclasses don't reimplement common boilerplate.

**Runtime player-aircraft selection** (`AircraftType`: f16, f18, f22, f22_cgtrader, f35): the menu's aircraft picker calls `SceneManager.SetPlayerAircraft` → `GameScene.setPlayerAircraft`. `FlightboxWithPhysics` records the request in a `PendingAircraftSwap` mailbox (thread-safe single-slot, latest wins) and applies it on the update thread at the top of `doUpdate` — the scene graph, physics world, and SceneManager registries are owned by the UpdateThread, so the UI callback never mutates them directly. `applyAircraftSwap` builds the new Aircraft + `SphereRigidBody`, swaps the rigid body in the physics entity list (`swappedEntities` — pure static helper, unit-tested Metal-free), re-attaches the persistent `AttachedCamera` using the aircraft's `cameraOffset` (per-subclass override on `Aircraft`, default `[0, 10, -20]`), removes the old aircraft via `SceneManager.RemoveObject`, and adds the new one. `buildScene` reuses the same path with `installEntities: false` (it installs the complete entity list once at the end).

**Deferred scene resets**: menu Reset button and Cmd+R call `SceneManager.RequestResetScene()`, which latches a `PendingSceneReset` (coalescing single-shot latch — the reset counterpart of `PendingAircraftSwap`). `SceneManager.Update` consumes it on the update thread at the top of the next unpaused tick and runs `TeardownScene` + `SetScene` — the old in-place teardown+rebuild from the input callback left previous objects registered and mutated `children` mid-traversal.

### Coordinate Conventions
**Left-handed Metal-native** throughout. Camera looks down +Z (forward); the main camera projection is **reverse-Z** — near maps to depth 1, far to 0 (`Transform.perspectiveProjection` is the single source of truth; clear depth is `Preferences.MainClearDepth = 0.0`). Depth-stencil states are named semantically: `CloserWrite`/`CloserNoWrite`/`CloserOrEqual*` map to `.greater`/`.greaterEqual` under reverse-Z. Shadow (light-space) passes remain forward-Z orthographic (clear 1.0, `.less`/`.lessEqual`). `Node.getFwdVector()` returns +column2 directly. Aircraft pitch/roll/yaw inputs are negated to keep pilot-perspective rotation directions stable. Model basis transforms with det<0 (e.g., Sketchfab F-22's `transformYMinusZXToXYZ`) are reindexed at import (`Mesh.reverseTriangleWinding()`) so the global `setFrontFacing(.clockwise) + setCullMode(.back)` works uniformly.

### SceneManager (Managers/SceneManager.swift)
Batches `ContiguousArray<GameObject>` per Model (opaque AND transparent — both feed `DrawManager.writeModelConstants` with no per-frame conversion) for instanced rendering. Separates opaque/transparent submeshes. Triple-buffered `RingBufferRegion` snapshots (offset, count, meshDatas) per frame. The update thread calls `writeFrameSnapshot(frameIndex:)` which writes ModelConstants directly into the per-frame ring buffer slot via `DrawManager.writeModelConstants` — no intermediate dict/array allocations on the render hot path. Render thread reads regions via `getOpaqueSnapshot/getTransparentSnapshot/getSkySnapshot`. Meshes with a non-identity animation transform get their transformed ModelConstants written ring-to-ring ONCE per frame by `DrawManager` (cached by mesh identity + source offset + absolute frame number; later passes re-bind the region; `TeardownScene` clears the cache). Transparent objects cache their MeshData arrays at registration time. Thread-safe via `OSAllocatedUnfairLock`.

**Register/Unregister via GameObjectType**: `Register` resolves `gameObject.objectType` once and dispatches through `add(_:to:)`; `Unregister` dispatches through `remove(_:from:)` using the `registeredObjectType` marker captured at registration (never re-derived — `isTransparent` can change via `setColor` between register and unregister). Both switches are exhaustive over `GameObjectType` with NO `default` — adding a case without handling both directions is a compile error; don't add a `default`. `.none` objects (cameras; lights live in LightManager) are fully unmanaged: no collection, no marker, so a persistent AttachedCamera can be reparented across aircraft swaps and re-enter subtree registration freely, while the double-register assert stays armed for batched types. `Unregister(node)` recurses the whole subtree (`subtreeNodes` — pure, Metal-free, unit-testable): composite objects register descendants FLAT in the batched collections (F-18 control surfaces in `modelDatas`, F-22 afterburners in `particleObjects`), so removing only the top node would leave frozen ghost renderables. `removeRenderable` drops a Model's entry once its last instance is gone. `SceneManager.RemoveObject(obj)` = `removeChild` + `Unregister`. SubMeshGameObject registration also hides the submesh in the parent model's draw lists (side effect, intentionally not undone on unregister — the parent's ModelData is rebuilt from scratch when re-registered).

**SetScene warm-up**: `SetScene` touches `Assets.Models[.Quad]` and `[.Icosahedron]` before building the scene — these are only ever referenced from the render thread, and the lazy model library would otherwise build them mid-encode under its lock on the first frame. `TeardownScene` also calls `SingleSubmeshMesh.clearCachedSourceModels()` to release parent MDLAssets retained for submesh extraction.

### Rendering System

**6 Renderer Types** (`RendererType` enum, switchable at runtime via the in-app menu on both macOS and iOS):

| Renderer | Shadow | GBuffer | MSAA | Tessellation | Particles |
|----------|--------|---------|------|--------------|-----------|
| SinglePassDeferredLighting | CSM 4×4096 depth32F array | 3 (albedo+spec, normal+shadow, depth) memoryless | No | No | No |
| TiledDeferred | CSM 4×4096 depth32F array | 4 (albedo, normal 16F, position 16F, lighting) memoryless | No | No | Yes |
| TiledDeferredMSAA | CSM 4×4096 depth32F array | 4 targets, 4x MSAA | 4x | No | Yes |
| TiledMSAATessellated | CSM 4×4096 depth32F array | 4 targets, 4x MSAA | 4x | Yes | Yes |
| OrderIndependentTransparency | None | None (image blocks) | No | No | No |
| ForwardPlusTileShading | — | — | — | — | — (stub) |

**Samplers & anisotropy**: `SamplerStateLibrary` pre-builds 5 immutable linear-sampler variants (`Linear_Anisotropy1x/2x/4x/8x/16x`); the `MaxAnisotropy` enum (raw value = `MTLSamplerDescriptor.maxAnisotropy`) drives the menu picker and maps to a variant. `currentLinearSamplerState` is a lock-guarded reference that switching anisotropy merely re-points (no Metal object creation; written from the UI thread, read per-pass on the render thread). The selection persists across launches via `Preferences.SelectedMaxAnisotropy` (UserDefaults key `graphics.maxAnisotropy`, factory default 8x). The linear sampler is pass-wide state: `DrawManager` binds it ONCE per pass via `bindLinearSampler` in the Draw* entry points (DrawOpaque/DrawTransparent/DrawPointLights/DrawIcosahedrons/DrawLines) — `applyMaterialTextures` deliberately does not bind it per submesh.

**Late drawable acquisition** (SinglePassDeferred, TiledDeferred, TiledMultisample, TiledMSAATessellated): per Apple's "acquire late, release early" guidance, each frame uses three command buffers — (1) Shadow CB, (2) Offscreen CB writing GBuffer/lighting/transparency/MSAA-resolve into an app-owned `lightingResolveTexture`, (3) Late CB that finally calls `view.currentDrawable`, runs a full-screen composite, and presents. Shrinks drawable hold window from milliseconds to tens of µs and reduces nextDrawable() stalls.

**framebufferOnly**: both platform view wrappers set `framebufferOnly = true` (Apple's default; lets Core Animation optimize drawable textures). This is safe because every renderer uses the drawable solely as a render-target attachment. Anything that needs to read the final frame (post-processing, screenshots) should sample `lightingResolveTexture`, not the drawable — don't flip this back to `false`.

**Frame pacing**: `inFlightSemaphore` with max 3 frames in flight. Render and update threads synchronize via `updateSemaphore` (render→update wakeup) and `updateDoneSemaphore` (update→render handshake): render signals the update thread at the START of the frame with the next ring-buffer slot index, waits for the update to finish, then encodes — this keeps ring-buffer ModelConstants and `_sceneConstants` (viewMatrix, cameraPosition, light data) consistent within the same frame, eliminating the camera/aircraft desync that occurred when reading data from different update generations.

### Asset System (AssetPipeline/)
Conventions for `Assets`, the lazy libraries, `TextureLoader`, model loading and meterization, materials, `SingleSubmeshMesh`, procedural meshes and the aircraft thumbnails live in `.claude/rules/asset-pipeline.md`, which loads automatically when you work under `ToyFlightSimulator Shared/AssetPipeline/`.

### Animation System (Animation/)
Conventions for `AnimationLayerSystem`, the channel types, skeleton conjugation and the aircraft animators live in `.claude/rules/animation.md`, which loads automatically when you work under `ToyFlightSimulator Shared/Animation/`.

### Physics and Flight Model (Physics/)
The rigid-body composition model, solvers, collision, landing gear, tires, steering, static structures, the flight model and the torque-driven attitude controller are documented in `.claude/rules/physics.md`, which loads automatically when you work under `ToyFlightSimulator Shared/Physics/`, the aircraft classes in `GameObjects/`, `StaticStructure.swift`, `Scenes/FlightboxWithPhysics.swift` or `ToyFlightSimulatorTests/Physics/`.

### Camera System (GameObjects/Cameras/)
`Camera` base (FOV, near/far, projection matrix from `Transform.perspectiveProjection`). `viewMatrix` is a lazy, generation-checked getter: it reads `modelMatrix` (bringing the world cache current), recomputes only when `worldMatrixGeneration` changed, and derives via the `computeViewMatrix(from:)` override point — base/`DebugCamera` use the plain inverse, so at most one inverse per camera per frame, and parent-following needs no per-frame hook. `DebugCamera` (WASD + mouselook). `AttachedCamera` (parents to node, follows aircraft; signature default offset `[0, 2, -4]` since +Z is forward, but scenes pass the aircraft's `cameraOffset` — a per-subclass override on `Aircraft`, default `[0, 10, -20]`) supports re-attachment for aircraft swaps: `attach(to:)` first detaches from any current parent and zeroes accumulated rotation. It overrides `computeViewMatrix` to strip parent scale via `scaleStrippedInverse()` — normalizes basis columns, keeps translation — so a camera on a scaled aircraft gets a rigid view matrix and view-space distances stay in true world units, which CSM cascade fitting depends on. `CameraManager.CurrentCamera` is now optional (`Camera?`) — guarded everywhere instead of force-unwrapped, so scene transitions and pre-scene-set states no longer crash. `CameraManager.Update()` skips parented cameras (they're updated through scene-graph traversal — prevents double `doUpdate`). 'C' key (`DiscreteCommand.CycleCamera`, debounced on the update thread in `GameScene.doUpdate`) cycles registered cameras in registration order; CameraManager's registry is an ordered identity-deduped array (registration order = cycle order = slot indices for `SetCamera(at:)` direct selection), scenes opt in by registering extra cameras via `addCamera(_, false)` (FlightboxWithPhysics adds a DebugCamera), and inactive cameras skip input via `isActiveCamera`.

### Shadows (Shadows/, Display/Protocols/ShadowRendering.swift, Shadow.metal, Lighting.metal)
4-cascade cascaded shadow maps. `ShadowCascadeFitting` splits the view frustum with the uniform/logarithmic hybrid (λ = 0.5), fits each slice with a rotation-invariant bounding sphere (radius depends only on FOV/aspect/slice depth, not camera rotation) and snaps the light-space origin to world-space texel multiples — together these kill shimmer as the camera moves. Straight-overhead sun is handled by building the light basis directly with an X-axis up-vector fallback instead of `Transform.look` (the old NaN-matrix bug). `ShadowCamera` wraps per-cascade view-projection + depth range; ortho Z padding is additive to bound casters when the depth range straddles 0.

Shadow map storage: one `depth32Float` `texture2DArray`, 4096² × 4 slices. `ShadowRendering` encodes one render pass per cascade, binding that cascade's VP at buffer index 13 (`TFSBufferIndexShadowCascadeVP`); no `setDepthBias` — bias is slope-scaled in-shader from `shadowWorldSlack`. Light space is forward-Z ortho (clear 1.0, `.less*`) even though the main camera is reverse-Z. Sampling (Lighting.metal): `SelectCascade` by view-space depth → 5×5 hardware `sample_compare` PCF → cross-fade to the next cascade over the last 10% of each cascade's range (`CASCADE_BLEND_FRACTION = 0.1`); out-of-bounds projection falls through to the next cascade (texel-snap edge case).

### Particles (GameObjects/Particles/)
`ParticleEmitter` descriptor-based (birth rate, life, speed, scale, color; physical units — speed m/s, life s). Predefined: Fire (1200-particle pool, upward), Afterburner (10k pool, aft). Emitters are **per-instance** — each F-22 nozzle owns its own pool/buffer (a shared static emitter used to double-step the shared sim by n·dt and leak the filled pool across scene teardowns/aircraft swaps; regression-tested in `AfterburnerEmitterTests`). Compute shader updates positions (dispatched over the born prefix only), render stage draws with appropriate pipeline.

### Threading
- **Main Thread**: Rendering (MTKView delegate), UI, input capture
- **UpdateThread**: Game logic + physics. Wakes on `updateSemaphore`, calls `SceneManager.writeFrameSnapshot(frameIndex:)` to write ModelConstants directly into the next ring-buffer slot, then signals `updateDoneSemaphore`. Delta time from `DispatchTime.now().uptimeNanoseconds`, clamped to `maxDeltaTime` (100 ms) so a parked thread (menu pause, occlusion, debugger — and the first-ever tick, whose previous time is 0) doesn't integrate the whole gap as one step; stalled time is dropped, not carried. Particle compute is additionally skipped while `SceneManager.Paused` (the async view-pause lets a frame or two draw with stale dt).
- **AudioThread**: Kicked after scene built (prevents crackling). Plays startup music if `Preferences.PlayMusicOnStartup`, otherwise calls `AudioManager.Prepare()` to build the lazy AVAudioEngine graph off-main so the first UI volume change doesn't stall the main thread. AVAudioEngine for MP3 playback
- **Synchronization**: `OSAllocatedUnfairLock` (managers, caches, input state), `DispatchSemaphore` (`inFlightSemaphore` for max 3 frames in flight; `updateSemaphore` + `updateDoneSemaphore` for render↔update handshake within a frame)

### Aircraft Telemetry (AircraftTelemetry/)
Pilot-facing flight data for the UI as a value snapshot, never a live object: `AircraftTelemetry` (Sendable struct; SI and degrees stored, knots/mph/feet as computed properties) is built on the UpdateThread by `Aircraft.getTelemetrySnapshot()` and published by `GameScene.update()` after `super.update()` (the frame's transforms are final there) at `telemetryPublishInterval` through a `Task { @MainActor }` hop into `AircraftTelemetryStore` (`@Observable @MainActor` singleton). Views read `latestSnapshot` inside `body`; neither store nor view holds an engine object, so aircraft swaps and scene resets need no re-pointing. The math is the pure `AircraftTelemetry.make` / `attitudeAngles(forward:right:up:)` (Metal-free, `AircraftTelemetryTests`): pitch = atan2(fwd.y, |fwd.xz|), heading = atan2(fwd.x, fwd.z) wrapped to [0, 360), roll = atan2(−right.y, up.y); below a 1e-6 horizontal nose length heading and roll are undefined and the previous snapshot's values are held. Forward speed is dot(velocity, forward), zero for aircraft without a rigid body (the kinematic path). Each `Aircraft` subclass passes its `AircraftType` to the base init (`aircraftType`), which the panel shows.

**HUD tapes** (`ToyFlightSimulator Shared/Views/`): `HeadingTape` (a full-width compass strip pinned to the top — a tick per degree, a label every 5°, the readout below), `SpeedTape` (knots, left edge, readout to its right) and `AltitudeTape` (feet, right edge, readout to its left) are thin wrappers that choose the unit, span, tick steps and text formatting and read `latestSnapshot`; `HorizontalTelemetryTapeView` / `VerticalTelemetryTapeView` draw the strip on a `Canvas` from the pure `TelemetryTapeLayout` enum (`TelemetryTapeLayoutTests`, Metal-free). Every tick sits at `centre + (value − current) × pointsPerUnit` along the strip (`tickX`; `tickY` subtracts instead, so values increase UPWARDS on the vertical tapes because SwiftUI's y grows downwards), so the current value is at the centre line by construction and heading labels wrap through 360 → 000 by modulo with no seam handling. Ticks and the centre line grow from the strip edge the readout sits against (`ReadoutPlacement`), labels are anchored at their near edge so any digit count reads away from its tick (the altitude strip is 52 pt wide for five digits), and the centre line shrinks to a stub when the current value is within a point-based clearance of a label (`isNearLabeledTick`, measured to the NEAREST label so negative speeds and altitudes work — a signed remainder would call every negative value near). The readout is `TelemetryTapeLayout.readout`, rounded rather than truncated (999.6 ft reads 1000, the label it sits under). Wrappers hide while `aircraftType == nil` (before the first publish, and in every scene without a player aircraft); the generic views draw nothing for a non-finite value and do every Int conversion, the readout's included, behind that guard (`Int(floor(x))` traps on NaN). The vertical tapes are inset 80 pt top and bottom to clear the heading tape and the telemetry panel by shortening the strip — `.contentMargins` only affects scrollable content and does nothing on a frame. `allowsHitTesting(false)` so the strips never take the scroll-wheel zoom, right-drag look or click picking that `GameView` reads through its AppKit responder overrides. Overlay layout rule learned here: an overlay in `MacGameUIView`'s `ZStack` must end with a frame the size of the WHOLE window plus an `alignment` (the `GameStats` / `AircraftTelemetryView` pattern) — a frame of the panel's own size gets centred by the stack, and its `alignment` then moves nothing (`debugging/claude/heading_tape_centered_no_labels_2026-09-18.md`). Off-screen check without launching the app: `debugging/claude/telemetry_tapes_render_2026-09-18.swift` compiles the Shared tape files with a stub telemetry store and renders the three tapes through `ImageRenderer` (build command in its header).

### Platform Differences & Menus
- **macOS**: NSViewRepresentable bridge (`MacMetalViewWrapper` in `Views/`), keyboard/mouse/HOTAS input, `GameViewController` captures key events. SwiftUI views (`MacGameUIView`, `GameStats`, `TFSMenu`) live in `ToyFlightSimulator macOS/Views/`; the HUD overlays it hosts (`HeadingTape`, `SpeedTape`, `AltitudeTape`, `AircraftTelemetryView`) live in `ToyFlightSimulator Shared/Views/` and compile into every target, like the shared menu controls.
- **iOS**: UIViewRepresentable bridge (`IOSMetalViewWrapper`), touch controls overlay, CoreMotion input. Views live in `ToyFlightSimulator iOS/Views/` (`IOSGameUIView`, `TFSMenuMobile`, touch controls). Defaults to `TiledMSAATessellated` but supports runtime renderer switching like macOS (`updateUIView` mirrors `updateNSView`'s teardown + re-init flow). SinglePassDeferredLighting doesn't work on iOS (memory issue). iOS/tvOS deployment targets are 26.0.
- **Menus**: both platforms compose the same shared controls from `ToyFlightSimulator Shared/Views/` — `RefreshRatePicker`, `VolumeSlider`, `RendererPicker`, `AnisotropyPicker`, `MetalHUDToggle`, `AircraftGridPicker` (X-Plane-style grid with generated thumbnails), `ResetSceneButton`. Put new menu controls there, not in per-platform copies. The stats overlay (`GameStats`, 'Y' key) shows FPS plus the active renderer via `GameStatsManager.currentRenderer` (set in `Renderer.init`).
- **Metal Performance HUD**: `MetalPerformanceHUD` (Utils/) toggles Apple's built-in HUD by setting `developerHUDProperties` on the drawable `CAMetalLayer`. Toggled via the shared menu switch on both platforms, or the 'H' key on macOS. The subsystem is armed by the `MTL_HUD_ENABLED=1` scheme env var; both view wrappers start it hidden.

## Key Development Patterns

Step-by-step registration recipes for adding game objects, shaders, models, player-selectable aircraft,
scenes, and renderers live in the **`extending-the-engine`** skill
(`.claude/skills/extending-the-engine/SKILL.md`) — invoke it when doing any of those.

The research, plan, and review stages of the working agreement are the `tfs-research`, `tfs-plan`, and
`tfs-review` skills (`.claude/skills/`). Each points at its template, restricts edits to its output
folder, and ends with a verification checklist. `tfs-research` runs in a forked context, so the full
question goes in its argument; `tfs-review` runs only when the owner invokes it.

## Testing

Two frameworks coexist:
- **XCTest**: `NodeTests`, `RendererTests` (unchanged legacy suites)
- **Swift Testing** (Apple's `@Test` framework, requires Xcode 26.2+): suites under `Math/`, `Utils/`, `AssetPipeline/`, `Cameras/`, `GameObjects/`, `Managers/`, `Physics/`, `Scenes/`, `Shadows/`, `Views/`. Shared helpers in `TestSupport/` (`ApproxEqual.swift` for Float/SIMD/matrix tolerance comparisons; `Finite.swift` for NaN/Inf checks on SIMD vectors/matrices; `TestTags.swift` for `.math`, `.utils`, `.concurrency`, `.assetPipeline`, `.physics`, `.gameObjects`, `.scenes` filtering). Concurrency tests use `.timeLimit(.minutes(1))` to fail fast on lock leakage.
- **What a test can see**: the test target compiles `ToyFlightSimulator Shared/` itself (its `TEST_HOST` is the macOS app, but no `BUNDLE_LOADER` is set, so the bundle links against nothing in the app). Only Shared types are reachable from a test; a symbol that exists only in a platform target is undefined at link time. Logic that needs a test therefore lives in Shared, never in `ToyFlightSimulator macOS/` or `iOS/` (the HUD tapes' geometry is `TelemetryTapeLayout` in `Shared/Views/` for exactly this reason). Xcode keeps a file's old membership when it is moved between synchronized groups by adding `membershipExceptions` for the other targets, so after moving a file into Shared check `git diff` on the pbxproj: the four HUD views arrived excluded from iOS, tvOS and the test target while their `SpeedTape`/`AltitudeTape` callers were not, which broke all three.

CI (`.github/workflows/`): test runs must pass `-parallel-testing-enabled NO` — serial execution avoids MTKView/CAMetalLayer drawable deadlocks in the app-hosted suite. Keep that flag. The macOS scheme and `ToyFlightSimulator macOS.xctestplan` have target parallelization off for the same reason (parallel IDE runs clone the app-hosted runner, launching one host-app instance per worker) — keep it off; Swift Testing's in-process concurrency is unaffected.

## Debugging

- **'C' key**: Cycle registered cameras in registration order (no-op in single-camera scenes). Debug: WASD + mouselook. Attached: follows aircraft
- **'Y' key**: Toggle stats display (FPS + active renderer)
- **'T' key** (macOS): Toggle the aircraft telemetry panel (`AircraftTelemetryView`: type, altitude, speed, heading, pitch, roll from `AircraftTelemetryStore`)
- **'H' key** (macOS; menu toggle on both platforms): Toggle Apple's Metal Performance HUD
- **'B' key**: Wheel brakes on the main gear, held = full (`ContinuousCommand.Brake` → `ControlInput.brake`; the tire model's longitudinal limit rises from 0.02·N to 0.52·N)
- **'X' key**: Cycle the collider debug overlay (`ColliderDebugOverlay`: off → volumes over hull → volumes only): red spec volumes, yellow legacy sphere, cyan strut lines; prints collider world dimensions and the gear stance when shown
- **ESC**: Toggle menu (pauses the game while open)
- **Cmd+R**: Reset scene (deferred to the update thread via `PendingSceneReset`; applies on the next unpaused tick)
- All textures are labeled for GPU debugger identification
