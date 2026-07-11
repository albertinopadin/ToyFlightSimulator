# ToyFlightSimulator Agent Guide

## Scope and Current Defaults

- The engine is Swift 6 + Metal, shared across macOS/iOS/tvOS under `ToyFlightSimulator Shared/`.
- Active runtime work is in `ToyFlightSimulator Shared/`; platform folders mainly contain SwiftUI/AppKit/UIKit wrappers and menus.
- Current starting scene: `Preferences.StartingSceneType = .FlightboxWithPhysics`.
- macOS and iOS root views default to `.TiledMSAATessellated` and expose a runtime renderer picker.
- `FlightboxWithPhysics` starts with the CGTrader F-22, a `SphereRigidBody`, `F22SimpleFlightModel`, an attached camera, a large ground plane, and random rigid-body objects.
- iOS and tvOS deployment targets are 26.0. `SinglePassDeferredLighting` is known to have a memory issue on iOS.
- The tvOS `GameViewController` is stale: it still calls the removed `Renderer(metalKitView:)` initializer. Do not treat tvOS as a verified runtime without repairing its bootstrap.

## Source Map

- `Animation/`: USD clips/skeletons/skins, animation channels/layers, aircraft animators, F-22/F-35 configs.
- `AssetPipeline/`: asset catalogs, `Mesh`/`Material`/`Model`, OBJ/USD loading, lazy asset libraries, F-18 submesh extraction, aircraft thumbnails. This folder replaced the old `Assets/` path.
- `Audio/`: `TFSAudioSystem` AVAudioEngine wrapper.
- `Core/`: engine bootstrap, preferences, game time, threads, input devices, shared library types, bundled models/audio.
- `Display/`: renderer classes plus reusable render/compute/shadow/particle/tessellation/GBuffer/late-present protocols.
- `GameObjects/`: scene graph, aircraft/weapons, cameras/lights, particles, terrain, `AircraftType`, `GameObjectType`.
- `Graphics/`: shader registry, render/compute/depth/sampler/vertex libraries, GBuffer textures, `.metal` shaders, `TFSCommon.h`.
- `Managers/`: global orchestration (`SceneManager`, `DrawManager`, `CameraManager`, `LightManager`, `InputManager`, `AudioManager`).
- `Math/`: `Transform` is the canonical matrix/projection implementation; `Math`/`MathUtils` hold remaining helpers.
- `Physics/`: rigid bodies, Euler/Verlet solvers, sweep-and-prune broad phase, collision response, flight models.
- `Scenes/`: scene composition and update logic, plus UI-to-update-thread mailboxes for aircraft swaps and scene resets.
- `Shadows/`: `ShadowCamera` and cascaded-shadow fitting.
- `Utils/`: locks/caches, ModelIO helpers, curves, finite-safe vector helpers, debug logging, random colors, Metal HUD control.
- `Views/`: shared macOS/iOS SwiftUI menu controls.
- `ToyFlightSimulatorTests/`: legacy XCTest plus Swift Testing suites for math, utils, assets, cameras, registration, physics, scenes, and shadows.
- `scripts/`: USD/material/skeleton and winding inspection utilities. `code_reviews/`, `debugging/`, `investigations/`, and `plans/` contain historical design context; verify against current source before following them.

## Runtime and Thread Flow (Critical)

1. A platform view wrapper's `makeCoordinator()` calls `Engine.Start(rendererType:)`.
2. `Engine.Start` starts the long-lived `UpdateThread` and `AudioThread`, creates three ModelConstants ring buffers, creates the renderer, and connects `updateSemaphore`/`updateDoneSemaphore`.
3. `makeNSView`/`makeUIView` creates `GameView`, sets Metal formats and `framebufferOnly = true`, assigns `Engine.MetalView`, then calls `SceneManager.SetScene(...)`.
4. `SetScene` warms the lazily loaded Quad/Icosahedron models, creates the scene, and `GameScene.initScene()` pauses around `buildScene()`. After build, the audio thread is kicked to play music or warm the AVAudioEngine graph off-main.
5. Once per rendered frame, `Renderer.render` selects the next ring-buffer slot, signals `UpdateThread` exactly once, then waits on `updateDoneSemaphore`.
6. On an unpaused tick, `SceneManager.Update` advances time, consumes a pending reset, updates cameras and the scene graph/physics, and writes ModelConstants directly into that slot. The update thread then signals completion.
7. The renderer calls `DrawManager.BeginFrame`, reads the matching snapshots/scene constants, and encodes the frame. This one-update handshake keeps camera and object data from different generations from being mixed.

Do not restore the old “signal before and after render” behavior; it caused two scene updates per frame. `UpdateThread` is an infinite semaphore loop. Pausing uses both `SceneManager.Paused` and `Engine.PauseView`; there is no thread teardown path.

## Scene Graph, Registration, and Runtime Mutation

- `Node` owns the transform hierarchy. Local T·R·S and parent×local world matrices are rebuilt lazily; transform setters mark the subtree dirty. `worldMatrixGeneration` lets cameras reuse their view matrix until the world transform actually changes.
- Override `doUpdate()`, not `update()`. `Node.update()` performs traversal, transform propagation, and dirty-state bookkeeping.
- `GameObject` extends `Node`, owns a `Model`, `ModelConstants`, and optional `rigidBody: RigidBody?`. It no longer conforms to `PhysicsEntity` itself.
- `GameScene.addChild` recursively registers every descendant `GameObject`. Bypassing it can leave an object in the hierarchy but absent from manager-driven draw/update passes.
- `GameObject.objectType` is the single registration declaration. The base class derives tessellated or opaque/transparent renderable categories; side-collection types override it. Cameras and lights use `.none` because `CameraManager`/`LightManager` own them.
- `SceneManager.Register` resolves `objectType` once and records it in `registeredObjectType`. `Unregister` uses that captured value, not mutable current state such as alpha.
- `SceneManager.add(_:to:)` and `remove(_:from:)` intentionally switch exhaustively over `GameObjectType` with no `default`. When adding a case, update both directions and keep the compiler exhaustiveness check.
- Registration flattens composite subtrees into manager buckets. Removal must recurse the subtree too; `SceneManager.Unregister` does this.
- Runtime despawns must call `GameObject.removeFromScene()`. For a direct scene child, `SceneManager.RemoveObject` is also available. A bare `parent?.removeChild(...)` leaves frozen render registrations and retained objects behind.
- Set object transparency before adding it to the scene. Changing object alpha afterward does not automatically rebucket it between opaque and transparent collections.
- `GameScene` provides `addGround(...)` and `setupDefaultSky()`. The default sky helper only adds a SkySphere for OIT or SkyBox for SinglePassDeferred; tiled renderers currently get no default sky.

### UI-to-update-thread handoffs

- Scene graph, physics entities, and SceneManager registrations are update-thread-owned during gameplay.
- Runtime aircraft selection flows `SceneManager.SetPlayerAircraft` → `GameScene.setPlayerAircraft` → `PendingAircraftSwap`; `FlightboxWithPhysics.doUpdate()` applies the latest request before physics.
- Scene reset flows through `SceneManager.RequestResetScene()` and `PendingSceneReset`; `SceneManager.Update` performs teardown/rebuild at the top of the next unpaused tick. Requests made while a menu pauses the view take effect after unpausing.
- Do not mutate these structures directly from a SwiftUI callback. Use the existing mailbox pattern for new UI-driven mutations.
- `SceneManager.TeardownScene` must precede a rebuild/renderer switch. It clears registries, ring snapshots, draw caches, lights/cameras, and retained F-18 source assets.

## Coordinate, Camera, and Depth Conventions

- The engine is left-handed and Metal-native. Camera/aircraft forward is +Z; `Node.getFwdVector()` returns column 2.
- The main perspective camera uses reverse-Z: near → 1, far → 0, clear depth `Preferences.MainClearDepth = 0.0`, and “closer” depth tests use `.greater`/`.greaterEqual`.
- Shadow projections remain forward-Z orthographic: clear 1.0 and use `.less`/`.lessEqual`. Do not mechanically convert shadow depth states to reverse-Z.
- `Transform.perspectiveProjection` is the canonical perspective implementation. Avoid reintroducing projection helpers in `Math`/`MathUtils`.
- Global raster convention is clockwise front faces with back-face culling. When an import basis has determinant < 0, `Mesh` reverses triangle winding. Direction vectors are transformed with w = 0.
- Mesh vertex basis conversion uses row-vector `v * B`, while shader skinning uses column-vector `J * v`; skeleton conjugation is `B^-1 * J * B`.
- `Camera.viewMatrix` is generation-cached. `AttachedCamera` strips inherited parent scale before inversion so view-space distances and shadow cascade fits remain world-scale-correct.
- `CameraManager.CurrentCamera` is optional; keep transition/pre-scene code guarded.

## Rendering Architecture

- Base class: `Renderer` (`MTKViewDelegate`). Current `RendererType` cases:
  - `OrderIndependentTransparency` → `OITRenderer` (image-block OIT; no CSM or particles).
  - `SinglePassDeferredLighting` → single-pass deferred + CSM; no particles.
  - `TiledDeferred` → tiled deferred + CSM + particles.
  - `TiledDeferredMSAA` → `TiledMultisampleRenderer`, 4× MSAA + CSM + particles.
  - `TiledMSAATessellated` → 4× MSAA + CSM + particles + terrain tessellation.
  - `ForwardPlusTileShading` → stub only.
- Shared mixins live in `Display/Protocols/`: `RenderPassEncoding`, `ComputePassEncoding`, `BaseRendering`, `ShadowRendering`, `ParticleRendering`, `TessellationRendering`, `TiledGBufferRendering`, and `LateDrawablePresenting`.
- Deferred renderers encode three command buffers per frame: shadow cascades, offscreen GBuffer/lighting/transparency work, then a late drawable composite/present. They render into an app-owned `lightingResolveTexture` and acquire `currentDrawable` only for the final pass.
- Both active platform wrappers keep `framebufferOnly = true`. Any post-process/readback must sample an app-owned intermediate (`lightingResolveTexture` for deferred renderers, the OIT base-color target for OIT), not the drawable.
- `ShadowRendering` owns one `depth32Float` 2D-array texture: four 4096×4096 slices, one render pass per cascade. `ShadowCascadeFitting` uses PSSM splits (λ 0.5), rotation-invariant bounding spheres, world-space texel snapping, and an overhead-sun-safe basis. Sampling uses 5×5 PCF, slope-scaled world-space bias, and a 10% cascade cross-fade.
- `RenderState` globally tracks current/previous pipeline state for the current animation PSO-switching workaround. Treat it as a hack when changing pass ordering or adding animated pipelines.

## Draw Path and Hot-Path Constraints

- `SceneManager` batches `ContiguousArray<GameObject>` by `Model`, with separate opaque and transparent registrations and cached `MeshData`.
- After updating, it writes ModelConstants directly into one of three shared ring buffers and publishes `RingBufferRegion` snapshots (offset/count/mesh data). The render path binds these regions instead of allocating a fresh `MTLBuffer` for each model draw.
- Mesh-local animation transforms are applied ring-to-ring once per mesh/frame and cached across GBuffer, transparency, and four shadow passes. Teardown clears this identity-keyed cache.
- `DrawManager.SetupAnimation` binds a skin palette and temporarily switches to an animated PSO. Preserve the non-skinned restoration path when changing pipeline state code.
- Linear samplers are pass-wide state. `DrawManager` binds the selected sampler once in each Draw* entry point; do not move the lock-backed lookup into the per-submesh material loop.
- `SceneManager.SetScene` and constructors resolve heavy/lazy draw-time assets off the render hot path. Avoid first-touch model/texture/library work while an encoder is active.
- Terrain tessellation uses position-only `TerrainControlPoint` buffers and dispatches one compute thread per patch. Keep CPU/Metal layouts and dispatch counts aligned.

## Shaders, Materials, and Samplers

- Add/rename Metal functions in `.metal` and register them in `ShaderLibrary` (`ShaderType`).
- Add a render pipeline through `RenderPipelineStateType`, a concrete state in `Graphics/Libraries/Pipelines/Render/`, and `RenderPipelineStateLibrary.makeLibrary()`.
- Add compute pipelines through `ComputePipelineStateType`, a concrete compute state, and `ComputePipelineStateLibrary.makeLibrary()`.
- Shared CPU/GPU structures, buffer/texture indices, and render-target indices live in `Graphics/Shaders/TFSCommon.h`; update Swift and Metal layouts together.
- `Material` imports base colors from `.color`, `.float3`, and `.float4`, and carries `MDLTextureSampler.transform` for base-color/normal/specular/opacity UV slots in `MaterialTextureTransforms`.
- Texture semantics are explicit: base color/emission load sRGB; normal/specular/roughness/metallic/AO/opacity load linear. `TextureLoader` defaults to bottom-left origin, private storage, and mipmap generation.
- Texture cache keys do not include the requested sRGB mode. The first load of a name/URL/MDLTexture wins, so do not request the same source with conflicting color-space semantics without redesigning the cache key/view strategy.
- `SamplerStateLibrary` prebuilds 1×/2×/4×/8×/16× anisotropic variants. The selected reference is lock-guarded and persisted in UserDefaults; factory default is 8×.

## Assets and Models

- Global libraries are `Assets.Meshes`, `Assets.SingleSMMeshes`, `Assets.Textures`, and `Assets.Models`.
- `ModelLibrary`, `TextureLibrary`, and `SingleSubmeshMeshLibrary` extend `LazyLibrary`: `makeLibrary()` registers factories, and first access builds/caches the value under the library lock. Factories may call other libraries but must not re-enter their own library.
- Model files live under `Core/Resources/Models/`. `ObjModel` and `UsdModel` generate tangent bases on the `MDLMesh` before creating `MTKMesh`.
- `SingleSubmeshMesh` lazily extracts F-18 weapons/control surfaces/fuel tanks. Sibling extractions share a cached parsed parent asset but take private vertex-buffer copies before basis/recentering mutations.
- F-18 pivot metadata stores its centroid in post-basis space. `setSubmeshOrigin` is absolute/idempotent because cached submeshes survive repeated aircraft swaps; do not make it cumulative again.
- Aircraft picker thumbnails live in `AssetPipeline/Thumbnails/`. SceneKit renders them offscreen on a serialized background actor; PNGs are cached under Caches using asset metadata + pose/config SHA256 keys.
- `AircraftThumbnailSpec.spec(for:)` and `ModelLibrary.makeLibrary()` must agree on model name/extension. Bump `ThumbnailCameraConfig.specVersion` after framing, lighting, pose, or generator changes. `TFS_REGEN_THUMBNAILS=1` bypasses the disk cache.

## Animation Patterns

- An `AnimationLayer` groups `AnimationChannel`s. Channel implementations include binary, continuous, and procedural input-driven channels; `AnimationMask` targets joints/meshes.
- `AnimationLayerSystem` sets `UsdModel.hasExternalAnimator = true`, runs dirty channels in two phases, and resolves channel→skeleton/mesh/joint mappings at registration. Keep string/dictionary discovery off its per-frame path.
- `Skeleton` caches inverse bind transforms, inverse basis, and joint-path indices, and writes world poses in place. Skin palettes update only for affected meshes/skeletons.
- `AircraftAnimator` is the base for `F22Animator` and `F35Animator`; typed `AnimationLayerID` values cover landing gear and F-22 control surfaces.
- `Aircraft.setupAnimator` centralizes the `UsdModel` cast. Base `Aircraft.doUpdate()` handles gear input and animator updates.
- `F22_CGTrader` adds procedural aileron/flaperon/stabilator/rudder inputs; stabilators mix pitch and roll. The legacy OBJ F-18 still uses extracted submesh/manual control-surface logic.

## Physics and Flight Model

- Physics uses composition: a `GameObject` has an optional `RigidBody`; `RigidBody` implements `PhysicsEntity` and weakly references its object. `SphereRigidBody` and `PlaneRigidBody` attach themselves in their initializer.
- `PhysicsWorld` intentionally stores concrete `[RigidBody]`, not protocol existentials. Revisit world, solver, collision, and broad-phase signatures together before adding a non-`RigidBody` physics entity.
- Gravity is currently `[0, -9.81, 0]`.
- Modes are `.NaiveEuler` (semi-implicit Euler) and `.HeckerVerlet` (Hecker response + velocity Verlet). Both consume sweep-and-prune candidate pairs when `useBroadPhase` is true and retain O(n²) paths for comparison.
- Broad phase computes each AABB once, sorts dynamic indices by cached min-X, and reuses scratch arrays. Its returned pair array is transient scratch: consume it within the same physics step and do not retain it.
- Collision response currently supports sphere-sphere and sphere-plane. Forces are accumulated before the physics step and cleared at the end; Verlet deliberately carries `acceleration` across steps.
- `FlightModel.computeForce(state:input:)` returns world-frame translational force from an immutable `RigidBody.State`. Only the F-22 variants currently attach `F22SimpleFlightModel` in `FlightboxWithPhysics`.
- `F22SimpleFlightModel` combines thrust, AOA-driven lift via `ValueCurve`, induced drag with a low-speed `SymmetricSigmoidCurve`, and parasitic drag. Use zero-safe `float3.normalize()` from `Float3+Extensions.swift` on rest/near-zero paths.
- Aircraft attitude remains kinematic rather than torque-integrated, but uses a frame-rate-independent, per-axis damped first-order rate response. Avoid reintroducing unconditional per-frame rotations that keep the entire aircraft/camera subtree dirty at rest.
- `Aircraft.flightModel` and `Aircraft.rigidBody` observers synchronize the duplicate mass fields. If mass becomes mutable at runtime, redesign this rather than adding another synchronization site.

## Input, UI, Audio, and Debug Controls

- `InputManager` merges keyboard, mouse, GameController, macOS HOTAS joystick/throttle, iOS motion, and iOS touch state into discrete/continuous commands. Use debounced helpers for toggles/actions.
- Shared menu views are `RefreshRatePicker`, `VolumeSlider`, `RendererPicker`, `AnisotropyPicker`, `MetalHUDToggle`, `AircraftGridPicker`, and `ResetSceneButton`. Put cross-platform menu controls in `ToyFlightSimulator Shared/Views/`, not duplicated platform folders.
- Platform root views own `AircraftThumbnailStore` so generated images survive closing/reopening the menu.
- Both active wrappers contain a runtime renderer-switch path using teardown → new renderer → `SetScene`, but see the semaphore wiring hazard below before relying on it.
- `MetalPerformanceHUD` writes `developerHUDProperties` on the drawable `CAMetalLayer`. The scheme must arm it with `MTL_HUD_ENABLED=1`; wrappers start it hidden.
- The audio thread starts with the engine but waits for scene build. With startup music disabled, it still constructs the lazy AVAudioEngine graph off-main so the first volume change does not stall UI.
- macOS shortcuts: `Y` stats overlay (including active renderer), `H` Metal HUD, `Esc` menu/pause, and `Cmd+R` deferred reset. Aircraft controls include `G` gear and `F` for the legacy F-18 flaps. `CameraManager` supports multiple camera types, but no current input path toggles them.

## Safe Extension Recipes

- New game object:
  1. Subclass `GameObject`/`Aircraft`/`ParticleEmitterObject`.
  2. Override `doUpdate()` only.
  3. Override `objectType` only for a side collection; if adding a new category, update both exhaustive SceneManager switches.
  4. Add through `GameScene.addChild(...)`.
  5. For physics, create a rigid body and add it to the scene's `PhysicsWorld`.
- New model:
  1. Add resources under `Core/Resources/Models/`.
  2. Add a `ModelType` case.
  3. Register a lazy factory in `ModelLibrary.makeLibrary()`.
  4. Resolve via `Assets.Models[...]`; arrange first heavy access off the render thread.
- New player-selectable aircraft:
  1. Add an `AircraftType` case.
  2. Add/model-register its `Aircraft` subclass.
  3. Handle it in `FlightboxWithPhysics.applyAircraftSwap`.
  4. Add a matching `AircraftThumbnailSpec` and tests.
  5. Override `cameraOffset` if the base `[0, 10, -20]` framing is wrong.
- New scene:
  1. Subclass `GameScene` and implement `buildScene()`.
  2. Add a `SceneType` case.
  3. Handle it exhaustively in `SceneManager.SetScene`.
- New renderer:
  1. Subclass `Renderer` and conform to the needed pass protocols.
  2. Implement `draw(in:)` and resize handling.
  3. Add a `RendererType` case and `Engine.InitRenderer` branch.
  4. If deferred, preserve late drawable acquisition and app-owned resolve targets.

## High-Risk Areas / Gotchas

- Many globals remain `nonisolated(unsafe)`; locking is selective. Do not infer thread safety from Swift 6 annotations.
- Manager registries rely heavily on ownership/handshake ordering. Keep UI mutations deferred and do not read/write ring slots outside the render↔update protocol.
- `SceneManager` model/side registries and teardown order are coupled to flat subtree registration.
- The wrapper renderer-switch path calls `Engine.InitRenderer` directly but does not reconnect the new renderer's `updateSemaphore`/`updateDoneSemaphore`; `Engine.Start` only wires the initial renderer. Treat live switching as incomplete until that ownership is centralized or the new renderer is wired safely.
- Lazy asset factories run while their library lock is held; self-reentry deadlocks. First-touching heavy assets during render causes stalls even when correct.
- Reverse-Z main depth and forward-Z shadow depth deliberately coexist.
- `framebufferOnly = true` is intentional; changing it hides architectural misuse of the drawable and costs performance.
- OIT has separate render-target behavior and does not conform to `LateDrawablePresenting`; do not assume every renderer shares the same pass flow.
- The current animation pipeline switching uses global mutable `RenderState`; runtime verification is required after PSO changes.
- F-18 extracted meshes are cached and mutated for pivots. Preserve private-buffer and idempotent-origin invariants.
- Several TODO/hack comments document live limitations. Avoid broad “cleanup” passes without targeted tests and runtime/GPU validation.

## Build and Test Commands

```bash
# macOS debug build
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# macOS release build
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Release CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# macOS tests (serial execution matches CI and avoids app-host/drawable deadlocks)
xcodebuild test -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug -parallel-testing-enabled NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# iOS simulator build
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator iOS" -sdk iphonesimulator -configuration Debug
```

- XCTest remains for `NodeTests` and `RendererTests`; newer suites use Swift Testing (`@Test`) and require Xcode 26.2 or newer.
- CI runs macOS tests on pushes and pull requests to `main` using `macos-26`, serial testing, and uploads `TestResults.xcresult` only on failure. A separate workflow performs the strict-concurrency macOS build.

## Style

- Follow existing Swift style: 4-space indentation, PascalCase types, camelCase members, and filenames aligned with their primary type.
- Preserve established enum/type naming even when unconventional unless the task explicitly includes a coordinated rename.
