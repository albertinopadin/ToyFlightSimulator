# CLAUDE.md

Guidance for Claude Code working with this Metal-based flight simulator for macOS/iOS/tvOS.

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

```
ToyFlightSimulator Shared/     # Cross-platform engine (~205 Swift files, 22 Metal shaders)
  Animation/                   # Skeletal animation, channels, layer system
    Animators/                 # AnimationController, AircraftAnimator base, F22Animator, F35Animator
    Configs/                   # F22AnimationConfig, F35AnimationConfig
    Layers/                    # AnimationChannel protocol, Binary/Continuous channels, AnimationLayer, masks
  AssetPipeline/               # Asset import + management (renamed from Assets/)
    Assets.xcassets            # Image/texture assets
    Libraries/Meshes/          # MeshLibrary, procedural meshes
    Libraries/Textures/        # TextureLoader (singleton cache), TextureLibrary
    Libraries/Models/          # ModelLibrary (OBJ/USDZ loading)
    Thumbnails/                # AircraftThumbnail Spec/Generator/Cache/Store (SceneKit picker thumbnails)
    Mesh.swift, Material.swift, ObjModel.swift, UsdModel.swift, etc.
  Audio/                       # TFSAudioSystem (AVAudioEngine wrapper)
  Core/
    Input/                     # Keyboard, Mouse, Joystick (HOTAS), Controller, MotionDevice
    Threads/                   # UpdateThread (game logic), AudioThread
    Types/                     # LazyLibrary (build-on-first-request Library base)
    Resources/Models/          # 3D model files (F16, F18, F22, F35, Temple, etc.)
  Display/                     # Renderers and protocols
    Protocols/                 # BaseRendering, ShadowRendering, ParticleRendering,
                               # TessellationRendering, TiledGBufferRendering, LateDrawablePresenting
  GameObjects/                 # Node → GameObject hierarchy, Aircraft, Weapons, Cameras, Particles
                               # AircraftType (player-selectable aircraft), GameObjectType (registration category)
  Graphics/
    Shaders/                   # All .metal files + TFSCommon.h shared definitions
    Libraries/Pipelines/       # Render/Compute pipeline states (~37 render pipeline cases + compute)
  Managers/                    # SceneManager, CameraManager, LightManager, DrawManager, AudioManager
  Math/                        # Math utilities (Transform.* is canonical, Math/MathUtils have niche helpers)
  Physics/
    World/                     # PhysicsWorld, PhysicsEntity protocol, RigidBody + Sphere/Plane subclasses
    Solver/                    # PhysicsSolver protocol, EulerSolver, VerletSolver
    BroadPhase/                # AABB, BroadPhaseCollisionDetector (sweep-and-prune)
    CollisionResponse/         # HeckerCollisionResponse
    FlightModel/               # FlightModel protocol, ControlInput, LiftData, Models/F22SimpleFlightModel
  Scenes/                      # GameScene subclasses (Flightbox, FlightboxWithPhysics, Sandbox, etc.)
                               # PendingAircraftSwap / PendingSceneReset (UI→update-thread mailboxes)
  Shadows/                     # ShadowCamera, ShadowCascadeFitting (CSM frustum fitting + texel snapping)
  Utils/                       # TFSCache, TFSLock, ModelIO extensions, ValueCurve, SymmetricSigmoidCurve,
                               # Float3+Extensions (zero-safe normalize), DebugLog, RandomColor,
                               # MetalPerformanceHUD (Apple HUD toggle via CAMetalLayer)
  Views/                       # SwiftUI views shared by macOS + iOS menus: AircraftGridPicker, RendererPicker,
                               # RefreshRatePicker, AnisotropyPicker, VolumeSlider, MetalHUDToggle, ResetSceneButton
ToyFlightSimulator macOS/
  Views/                       # MacMetalViewWrapper, MacGameUIView, GameStats, TFSMenu (SwiftUI)
  AppDelegate.swift, GameViewController.swift
ToyFlightSimulator iOS/
  Views/                       # IOSMetalViewWrapper, IOSGameUIView, TFSMenuMobile, touch controls
                               # (virtual joystick/throttle)
ToyFlightSimulator tvOS/       # tvOS target
ToyFlightSimulatorTests/       # XCTest: NodeTests, RendererTests (legacy)
                               # Swift Testing: Math/, Utils/, AssetPipeline/, Cameras/, GameObjects/,
                               # Managers/, Physics/, Scenes/, Shadows/, TestSupport/
code_reviews/ debugging/ investigations/ plans/   # Claude-authored review, debugging, research, and plan docs
                               # (claude/ subdirs; debugging/screenshots/ holds visual artifacts)
```

## Architecture

### Initialization Flow
1. Platform entry point creates SwiftUI view containing MetalViewWrapper
2. MetalViewWrapper's `makeCoordinator()` calls `Engine.Start(rendererType:)` which starts UpdateThread + AudioThread
3. `makeNSView/makeUIView` creates `GameView` (MTKView subclass), sets `Engine.MetalView`
4. `SceneManager.SetScene()` creates a GameScene subclass which calls `buildScene()` to populate scene graph
5. Renderer assigned as MTKView delegate starts the render loop

### Engine (Core/Engine.swift)
Static lazy initialization of `MTLDevice`, `MTLCommandQueue`, `MTLLibrary`. Owns renderer, UpdateThread, AudioThread.

### Scene Graph
- **Node**: Base class with transform hierarchy (position, rotation, scale). `modelMatrix = parentModelMatrix * localMatrix`, both lazily cached: setters only flag dirty (no eager T·R·S rebuild), the getter rebuilds local + composed world on first read and bumps `worldMatrixGeneration` (derived consumers like `Camera.viewMatrix` compare generations instead of recomputing). `update()` computes the world matrix once for all children. `getRotationEulers()` returns all three angles from one decomposition. Children updated recursively via `update()` → `doUpdate()`.
- **GameObject**: Extends Node. Has `Model` (meshes + materials), `ModelConstants` (shader uniforms), and an optional `rigidBody: RigidBody?` for physics (composition — GameObject no longer implements `PhysicsEntity` itself). `Hashable` for collection use. `objectType: GameObjectType` declares which SceneManager collection it batches into (base class derives Tessellatable / opaque-vs-transparent automatically; subclasses in side collections override — SkyBox/SkySphere → `.sky`, Camera → `.none`, etc.). `registeredObjectType` is the marker SceneManager sets at registration and consumes at unregistration. Runtime despawns (weapons reaping themselves) must call `removeFromScene()` — a bare `parent?.removeChild(self)` leaves the object registered, so it keeps being drawn at its last position and never deallocates.
- **GameScene**: Root node. `buildScene()` overridden by subclasses. `addChild()` auto-registers with SceneManager. Has `addCamera()`, `addLight()` helpers. Holds `playerAircraft: Aircraft?` and a `setPlayerAircraft(_:)` override point for scenes that support runtime aircraft swapping.

### Scenes (Scenes/)
`GameScene` subclasses: `FlightboxScene`, `FlightboxWithTerrain`, `FlightboxWithPhysics`, `FreeCamFlightboxScene`, `SandboxScene`, `BallPhysicsScene`, `PhysicsStressTestScene`. Default starting scene set in `Preferences.StartingSceneType` (currently `.FlightboxWithPhysics`: player aircraft — default CGTrader F-22 — with `SphereRigidBody` + `F22SimpleFlightModel`, animatable gear, plus optional random rigid-body objects).

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

**Render pass flow** (typical deferred): Shadow cascade passes (one per cascade) → GBuffer generation → Directional lighting → Transparency → Point light volumes (stencil-masked icosahedrons) → Skybox → (Particles if supported) → Late composite into drawable

**Key rendering protocols** (Display/Protocols/): `RenderPassEncoding`, `ComputePassEncoding`, `BaseRendering`, `ShadowRendering` (shadow-map array creation + per-cascade pass encoding; `ShadowMapSize = 4096`, `CascadeCount = 4`), `ParticleRendering`, `TessellationRendering`, `TiledGBufferRendering` (default `setGBufferTextures`/`setDepthAndStencilTextures` for the three tiled deferred renderers), `LateDrawablePresenting` (drawable acquisition + composite). Renderers compose these via protocol conformance.

**Pipeline states**: ~37 render pipeline cases (+ compute) in `RenderPipelineStateLibrary`, created via factory pattern. Each renderer type has its own set of pipelines defined in dedicated files (SinglePassDeferredPipeline, TiledDeferredPipeline, etc.). `RenderPipelineState` protocol extension provides `enableBlending(...)` (alpha) and `enableAdditiveBlending(...)` (point-light volume path).

**Samplers & anisotropy**: `SamplerStateLibrary` pre-builds 5 immutable linear-sampler variants (`Linear_Anisotropy1x/2x/4x/8x/16x`); the `MaxAnisotropy` enum (raw value = `MTLSamplerDescriptor.maxAnisotropy`) drives the menu picker and maps to a variant. `currentLinearSamplerState` is a lock-guarded reference that switching anisotropy merely re-points (no Metal object creation; written from the UI thread, read per-pass on the render thread). The selection persists across launches via `Preferences.SelectedMaxAnisotropy` (UserDefaults key `graphics.maxAnisotropy`, factory default 8x). The linear sampler is pass-wide state: `DrawManager` binds it ONCE per pass via `bindLinearSampler` in the Draw* entry points (DrawOpaque/DrawTransparent/DrawPointLights/DrawIcosahedrons/DrawLines) — `applyMaterialTextures` deliberately does not bind it per submesh.

**Late drawable acquisition** (SinglePassDeferred, TiledDeferred, TiledMultisample, TiledMSAATessellated): per Apple's "acquire late, release early" guidance, each frame uses three command buffers — (1) Shadow CB, (2) Offscreen CB writing GBuffer/lighting/transparency/MSAA-resolve into an app-owned `lightingResolveTexture`, (3) Late CB that finally calls `view.currentDrawable`, runs a full-screen composite, and presents. Shrinks drawable hold window from milliseconds to tens of µs and reduces nextDrawable() stalls.

**framebufferOnly**: both platform view wrappers set `framebufferOnly = true` (Apple's default; lets Core Animation optimize drawable textures). This is safe because every renderer uses the drawable solely as a render-target attachment. Anything that needs to read the final frame (post-processing, screenshots) should sample `lightingResolveTexture`, not the drawable — don't flip this back to `false`.

**Frame pacing**: `inFlightSemaphore` with max 3 frames in flight. Render and update threads synchronize via `updateSemaphore` (render→update wakeup) and `updateDoneSemaphore` (update→render handshake): render signals the update thread at the START of the frame with the next ring-buffer slot index, waits for the update to finish, then encodes — this keeps ring-buffer ModelConstants and `_sceneConstants` (viewMatrix, cameraPosition, light data) consistent within the same frame, eliminating the camera/aircraft desync that occurred when reading data from different update generations.

### Shader System (Graphics/Shaders/)
22 Metal files. Shared definitions in `TFSCommon.h` (buffer indices, vertex attributes, texture indices, render target indices, struct definitions for ModelConstants, SceneConstants, MaterialProperties, LightData, Particle, Terrain). `ShaderDefinitions.h` has GBuffer output struct with raster order groups.

**Pixel formats** (Preferences.swift): `bgra8Unorm_srgb` (main), `depth32Float` (depth), `depth32Float_stencil8` (depth+stencil). `MainClearDepth = 0.0` (reverse-Z far plane).

### Asset System (AssetPipeline/)
**Assets** singleton: `Assets.Meshes` (MeshLibrary), `Assets.Textures` (TextureLibrary), `Assets.Models` (ModelLibrary), `Assets.SingleSMMeshes` (SingleSubmeshMeshLibrary). All extend the generic `Library<Key, Value>` base; Textures/Models/SingleSMMeshes are `LazyLibrary` subclasses (Core/Types/LazyLibrary.swift): `makeLibrary()` registers a factory per key, the factory runs once on first request under the library lock, and the value is cached for the process lifetime (`setResolved` injects runtime-created values like render targets). Factories may use other libraries/caches (distinct locks) but must never re-enter the same library, and first access to a heavy asset should happen off the render thread — see the `SceneManager.SetScene` warm-up; SkyBox/SkySphere resolve their sky texture at construction so `DrawSky` never touches the texture library's locked subscript, and `DrawManager` caches its draw-time Quad/Icosahedron references after first resolve.

**TextureLoader**: Singleton MTKTextureLoader with 3-level TFSCache (by String, URL, MDLTexture). Auto-generates mipmaps, uses `.private` storage mode. Thread-safe. Default texture origin is `.bottomLeft` consistently across entry points. All entry points take `srgb: Bool?` (default `nil` = honor file metadata; `true`/`false` force sRGB/linear). `Material` wires it per semantic via `isSRGBSemantic`: `.baseColor`/`.emission` load sRGB, data maps (normal, specular, roughness, metallic, AO, opacity) load linear. Caveat: cache keys do NOT include srgb — first load of a given name/URL wins, fine while per-semantic settings stay consistent.

**Model loading**: `ObjModel` (OBJ+MTL via ModelIO; accepts a basis transform), `UsdModel` (USDZ with skeleton/animation/skin support). Both use custom vertex descriptor (position, color, texcoord, normal, tangent, bitangent, joints, jointWeights). Tangent bases generated on the MDL mesh before the MTK mesh is created.

**Material UV transforms**: `MDLTextureSampler.transform` is captured per slot (baseColor, normal, specular, opacity) at import time, stored as `matrix_float3x3` in `MaterialTextureTransforms` and bound at fragment buffer index 12 (`TFSBufferIndexMaterialTextureTransforms`). A `hasTextureTransforms` bool gates the UV `mat3` multiply so the identity path is branch-free. Mirrors glTF KHR_texture_transform / USD UsdTransform2d semantics.

**Material color extraction**: `Material.populateMaterial()` handles `.color`, `.float3`, `.float4` for the `.baseColor` semantic only — earlier code only handled `.color`, which silently dropped USD float3 base colors and caused the default init color to bleed into untextured submeshes (F22 canopy/HUD glass).

**SingleSubmeshMeshLibrary / SingleSubmeshMesh**: Extracts individual submeshes from parent models (F18 weapons, control surfaces, fuel tanks). Extraction is lazy per submesh; the parsed parent `MDLAsset` (parse + `loadTextures()`) is cached so sibling extractions reuse it, and `SceneManager.TeardownScene` releases those parents via `clearCachedSourceModels()` (extracted meshes stay in the library cache). Each extracted mesh takes a PRIVATE copy of the shared parent vertex buffer (`Mesh.init(copyVertexBuffer: true)`) so in-place basis transforms/recentering can't corrupt siblings. `SingleMeshVertexMetadata`'s centroid is mapped into post-basis space (`transformingCentroid(by:)`, same row-vector `v*B` convention as `Mesh.transformMeshBasis`; min/max bounds stay pre-basis) so origin/pivot math in F18's `setupControlSurfaces` works in the same space as the vertices. `setSubmeshOrigin` is absolute/idempotent (tracks the applied origin) — an F-18 rebuilt across repeated aircraft swaps shares the one cached mesh, and re-applying the same origin must not accumulate (the old control-surface drift bug).

**Procedural meshes**: Triangle, Quad, Cube, Sphere, Capsule, Plane, Skybox, SkySphere, Icosahedron. Built on MDLMesh factory constructors with `addTangentBasis` applied before MTKMesh creation — hand-rolled vertex buffers didn't land where MTKMesh expects (the old cubes/triangles-not-rendering bug).

**Aircraft picker thumbnails** (AssetPipeline/Thumbnails/): X-Plane-style card images for the menu's `AircraftGridPicker`. `AircraftThumbnailSpec` defines one per-`AircraftType` pose (model name/extension mirrors `ModelLibrary.makeLibrary()` — keep in sync when adding aircraft) plus a SHA256 cache key covering pose constants, `ThumbnailCameraConfig.specVersion` (bump to invalidate all cached thumbnails after framing/lighting changes), and the model file's size+mtime. `AircraftThumbnailGenerator` renders offscreen via SceneKit `SCNRenderer` (no view/window — safe off the main thread while the game owns the MTKView); USDZ loads through SceneKit's native importer, OBJ through ModelIO with material sanitization (ModelIO's OBJ bridge can produce scalar `transparent` = opacity 0 and blown-out white PBR `emission`). `AircraftThumbnailCache` is a PNG disk cache under Caches/, pruning stale generations per aircraft. `AircraftThumbnailStore` (`@Observable @MainActor`, owned by the platform root view so thumbnails survive menu close/reopen) serializes renders through a background actor. Env var `TFS_REGEN_THUMBNAILS=1` bypasses the cache.

### Animation System (Animation/)
**AnimationController** protocol with playback state management. **AnimationLayerSystem** manages layers and channels with dirty-flag optimization. Channel→skeleton/mesh affinity AND per-joint resolution happen once at registration: `ChannelMapping.SkeletonEntry` carries the resolved `Skeleton` reference, clip, `(jointIndex, animation)` pairs (clip channels), and joint indices (procedural channels) — the per-frame path does no String/dictionary lookups. `Skeleton` caches `inverseBindTransforms`, the basis inverse, and a `jointIndexByPath` map at init, and `evaluateWorldPoses()` writes `currentPose` in place (allocation-free; bind-inverse + basis conjugation fused). `Animation` keyframe sampling scans for the bracketing pair without materializing a pairs array; procedural channels fill a reused rotation scratch buffer (axes pre-normalized in `ProceduralJointConfig.init`).

**Channel types** (individual animated elements):
- `BinaryAnimationChannel`: Two-state (landing gear up/down). States: inactive → activating → active → deactivating. Progress-based smooth transitions.
- `ContinuousAnimationChannel`: Variable-position (flaps, control surfaces). Value range with `transitionSpeed`.

**AnimationLayer**: Groups related channels that animate together to form a discrete animation (e.g., all the channels needed to extend the landing gear). **AnimationMask** for selective joint targeting. Skeleton/skin palette updates per channel. Layer IDs are typed via `enum AnimationLayerID: String` (cases: `landingGear`, `flaperon`, `aileron`, `horizontalStabilizer`, `rudder`) defined once in `AircraftAnimator.swift`.

**Skeleton conjugation**: `Skeleton.evaluateWorldPoses` and `TransformComponent` use `B^-1 * J * B` (not `B * J * B^-1`). Mesh transform is row-vector (`v_engine = v*B`); shader skins as column-vector (`J*v`). Matters for proper rotations even though it's a no-op for symmetric/self-inverse axis-swap basis matrices.

**Aircraft animators**: `AircraftAnimator` base → `F35Animator`, `F22Animator`. `Aircraft` base provides `setupAnimator<A: AircraftAnimator>(_ make: (UsdModel) -> A)` (handles UsdModel cast + warning) and a default `doUpdate()` that runs gear-toggle input and `animator?.update(deltaTime:)`. Subclasses only override `doUpdate` if they need procedural per-frame logic beyond the animator (e.g., `F22_CGTrader` for ailerons/flaperons/horizontal stabs/rudders). `Aircraft.isGearDown` returns `animator?.isGearDown ?? true`.

### Physics (Physics/)
**Composition model**: `GameObject` *has* a `rigidBody: RigidBody?` (it no longer *is* a `PhysicsEntity`). `RigidBody` (class, `World/RigidBody.swift`) implements the `PhysicsEntity` protocol (collisionShape, mass, velocity, acceleration, force, restitution, isStatic, shouldApplyGravity, AABB accessors; identity is `ObjectIdentifier` — no stored id — and `collidedWith` is a `Set<ObjectIdentifier>` reset each step) and holds a weak back-reference to its GameObject; its initializer self-registers via `gameObject?.rigidBody = self` (the parameter is optional so tests can build Metal-free `RigidBody` doubles — see `TestRigidBody` in PhysicsSolverTests). `BasicRigidBodies.swift`: `SphereRigidBody` (collisionRadius) and `PlaneRigidBody` (collisionNormal, normalized at init so collision response never re-normalizes). `RigidBody.State` is an immutable snapshot (mass, velocity, world axes, rotation matrix) consumed by flight models.

**PhysicsWorld**: entity registry (`addEntity/addEntities/setEntities`) storing concrete `[RigidBody]` — not `[any PhysicsEntity]` — for direct class dispatch in solver loops (see the NOTE in PhysicsWorld.swift if a non-RigidBody entity type is ever added). Runs in UpdateThread. Per `updateType`: `.NaiveEuler` (pair-consuming `EulerSolver.step(...collisionPairs:)`) or `.HeckerVerlet` (HeckerCollisionResponse + VerletSolver); BOTH consume broad-phase candidate pairs, with `useBroadPhase = false` falling back to legacy O(n²) comparison paths. **Force lifecycle** per step: apply forces → resolve collisions → integrate/move → `zeroForces()`. **Solvers**: `PhysicsSolver` protocol (`static func step(deltaTime:gravity:entities:)`); `EulerSolver` (semi-implicit Euler), `VerletSolver` (velocity Verlet — `entity.acceleration` carries a(t) across steps, `a = F/m + g`). Narrow phase uses squared-distance compares (no pow/sqrt on reject paths). **Collision**: `BroadPhaseCollisionDetector` (X-axis sweep-and-prune; AABBs computed once per entity per frame into reused scratch arrays, index sort on cached min-x keys, stats opt-in via `collectStatistics` — the returned pairs array is reused scratch, consume within the step), `HeckerCollisionResponse` (sphere-sphere, sphere-plane).

### Flight Model (Physics/FlightModel/)
**FlightModel** protocol: `computeForce(state: RigidBody.State, input: ControlInput) -> float3` — pure function from rigid-body snapshot + controls to a world-frame force. `ControlInput` (throttle 0–1; pitch/roll/yaw −1…1) flows InputManager → `Aircraft`. Attachment: `Aircraft.flightModel` (optional); `flightModel.didSet` and `F22.rigidBody.didSet` both sync `rigidBody.mass` so either assignment order converges (duplicate mass field — documented future cleanup in Aircraft.swift).

**F22SimpleFlightModel** sums: engine thrust (`worldForward * maxThrust * throttle`), world-frame lift (AOA from local-frame velocity → Cl via a Catmull-Rom `ValueCurve` spanning −30°…+120°; force perpendicular to wing-plane velocity), induced drag (∝ Cl², ramped in via `SymmetricSigmoidCurve` to suppress it below ~5 m/s), and simple parasitic drag. `LiftData` captures intermediate aero values. Zero-safe `normalize()` from `Float3+Extensions` keeps NaNs out at rest.

**Attitude**: rotation is kinematic, not torque-driven — `Aircraft` runs a per-axis damped first-order lag filter (`AttitudeDynamics`: maxRate + timeConstant τ per axis; rates carried across frames, decay when unfocused). Rates snap to exactly 0 below ~1e-4 rad/s and a zero side-stick skips the move entirely, so a settled aircraft issues no transform writes (keeps its subtree clean). See `plans/claude/damped_attitude_response.md`.

### Input (Core/Input/)
Platform-abstracted via `InputManager` singleton. **macOS**: Keyboard (256-key state array), Mouse (buttons + delta + scroll), GameController (GCController), Joystick/Throttle (Thrustmaster Warthog HOTAS via IOKit HID). **iOS**: CoreMotion (attitude at 60Hz), TFSTouchJoystick/TFSTouchThrottle. Commands: `DiscreteCommands` (fire, toggle gear/flaps), `ContinuousCommands` (pitch, roll, yaw, move). Debouncing for discrete commands.

### Camera System (GameObjects/Cameras/)
`Camera` base (FOV, near/far, projection matrix from `Transform.perspectiveProjection`). `viewMatrix` is a lazy, generation-checked getter: it reads `modelMatrix` (bringing the world cache current), recomputes only when `worldMatrixGeneration` changed, and derives via the `computeViewMatrix(from:)` override point — base/`DebugCamera` use the plain inverse, so at most one inverse per camera per frame, and parent-following needs no per-frame hook. `DebugCamera` (WASD + mouselook). `AttachedCamera` (parents to node, follows aircraft; signature default offset `[0, 2, -4]` since +Z is forward, but scenes pass the aircraft's `cameraOffset` — a per-subclass override on `Aircraft`, default `[0, 10, -20]`) supports re-attachment for aircraft swaps: `attach(to:)` first detaches from any current parent and zeroes accumulated rotation. It overrides `computeViewMatrix` to strip parent scale via `scaleStrippedInverse()` — normalizes basis columns, keeps translation — so a camera on a scaled aircraft gets a rigid view matrix and view-space distances stay in true world units, which CSM cascade fitting depends on. `CameraManager.CurrentCamera` is now optional (`Camera?`) — guarded everywhere instead of force-unwrapped, so scene transitions and pre-scene-set states no longer crash. `CameraManager.Update()` skips parented cameras (they're updated through scene-graph traversal — prevents double `doUpdate`). Toggle with 'C' key.

### Lighting (GameObjects/LightObject.swift, Managers/LightManager.swift)
`LightObject` extends GameObject. Types: Directional, Point. `Sun` subclass for main directional light. `LightObject.updateShadowCascades()` refits the CSM cascades every frame from the live camera; `LightData` (TFSCommon.h) carries `cascadeCount`, `cascadeViewProjectionMatrices[4]`, `cascadeSplitDepths[4]`, `cascadeDepthRanges[4]`, and `shadowWorldSlack` (base world-space depth epsilon). `LightManager` singleton (thread-safe) provides light data arrays to shaders via reused scratch buffers, plus a cheap `PointLightCount` for render-side branching (avoids materializing `[LightData]` just to check counts). Point lights rendered as icosahedron instances with stencil masking.

### Shadows (Shadows/, Display/Protocols/ShadowRendering.swift, Shadow.metal, Lighting.metal)
4-cascade cascaded shadow maps. `ShadowCascadeFitting` splits the view frustum with the uniform/logarithmic hybrid (λ = 0.5), fits each slice with a rotation-invariant bounding sphere (radius depends only on FOV/aspect/slice depth, not camera rotation) and snaps the light-space origin to world-space texel multiples — together these kill shimmer as the camera moves. Straight-overhead sun is handled by building the light basis directly with an X-axis up-vector fallback instead of `Transform.look` (the old NaN-matrix bug). `ShadowCamera` wraps per-cascade view-projection + depth range; ortho Z padding is additive to bound casters when the depth range straddles 0.

Shadow map storage: one `depth32Float` `texture2DArray`, 4096² × 4 slices. `ShadowRendering` encodes one render pass per cascade, binding that cascade's VP at buffer index 13 (`TFSBufferIndexShadowCascadeVP`); no `setDepthBias` — bias is slope-scaled in-shader from `shadowWorldSlack`. Light space is forward-Z ortho (clear 1.0, `.less*`) even though the main camera is reverse-Z. Sampling (Lighting.metal): `SelectCascade` by view-space depth → 5×5 hardware `sample_compare` PCF → cross-fade to the next cascade over the last 10% of each cascade's range (`CASCADE_BLEND_FRACTION = 0.1`); out-of-bounds projection falls through to the next cascade (texel-snap edge case).

### Particles (GameObjects/Particles/)
`ParticleEmitter` descriptor-based (birth rate, life, speed, scale, color). Predefined: Fire (1200 particles, upward), Afterburner (1200, forward). Compute shader updates positions, render stage draws with appropriate pipeline.

### Threading
- **Main Thread**: Rendering (MTKView delegate), UI, input capture
- **UpdateThread**: Game logic + physics. Wakes on `updateSemaphore`, calls `SceneManager.writeFrameSnapshot(frameIndex:)` to write ModelConstants directly into the next ring-buffer slot, then signals `updateDoneSemaphore`. Delta time from `DispatchTime.now().uptimeNanoseconds`.
- **AudioThread**: Kicked after scene built (prevents crackling). Plays startup music if `Preferences.PlayMusicOnStartup`, otherwise calls `AudioManager.Prepare()` to build the lazy AVAudioEngine graph off-main so the first UI volume change doesn't stall the main thread. AVAudioEngine for MP3 playback
- **Synchronization**: `OSAllocatedUnfairLock` (managers, caches, input state), `DispatchSemaphore` (`inFlightSemaphore` for max 3 frames in flight; `updateSemaphore` + `updateDoneSemaphore` for render↔update handshake within a frame)

### Platform Differences & Menus
- **macOS**: NSViewRepresentable bridge (`MacMetalViewWrapper` in `Views/`), keyboard/mouse/HOTAS input, `GameViewController` captures key events. SwiftUI views (`MacGameUIView`, `GameStats`, `TFSMenu`) live in `ToyFlightSimulator macOS/Views/`.
- **iOS**: UIViewRepresentable bridge (`IOSMetalViewWrapper`), touch controls overlay, CoreMotion input. Views live in `ToyFlightSimulator iOS/Views/` (`IOSGameUIView`, `TFSMenuMobile`, touch controls). Defaults to `TiledMSAATessellated` but supports runtime renderer switching like macOS (`updateUIView` mirrors `updateNSView`'s teardown + re-init flow). SinglePassDeferredLighting doesn't work on iOS (memory issue). iOS/tvOS deployment targets are 26.0.
- **Menus**: both platforms compose the same shared controls from `ToyFlightSimulator Shared/Views/` — `RefreshRatePicker`, `VolumeSlider`, `RendererPicker`, `AnisotropyPicker`, `MetalHUDToggle`, `AircraftGridPicker` (X-Plane-style grid with generated thumbnails), `ResetSceneButton`. Put new menu controls there, not in per-platform copies. The stats overlay (`GameStats`, 'Y' key) shows FPS plus the active renderer via `GameStatsManager.currentRenderer` (set in `Renderer.init`).
- **Metal Performance HUD**: `MetalPerformanceHUD` (Utils/) toggles Apple's built-in HUD by setting `developerHUDProperties` on the drawable `CAMetalLayer`. Toggled via the shared menu switch on both platforms, or the 'H' key on macOS. The subsystem is armed by the `MTL_HUD_ENABLED=1` scheme env var; both view wrappers start it hidden.

## Key Development Patterns

### Adding New Game Objects
1. Extend `GameObject` (or `Aircraft` for vehicles)
2. Override `doUpdate()` for per-frame logic
3. Add to scene via `addChild()` in a `GameScene.buildScene()` override
4. SceneManager auto-registers for batched rendering (base `objectType` handles opaque/transparent/tessellatable; override it — and extend `GameObjectType` + both `add`/`remove` switches — only for a new side collection)
5. For physics: construct a `SphereRigidBody`/`PlaneRigidBody` (self-attaches to the GameObject) and register it with the scene's `PhysicsWorld` via `addEntity()`
6. Runtime despawns must use `removeFromScene()`, not bare `parent?.removeChild(self)` (see Scene Graph)

### Adding New Shaders
1. Add Metal functions to appropriate .metal file (or new file)
2. Add enum case to `RenderPipelineStateType`
3. Create pipeline state struct in relevant pipeline library file
4. Register in `RenderPipelineStateLibrary.makeLibrary()`
5. Use in renderer via `setRenderPipelineState(encoder, state: .NewType)`

### Adding New Models
1. Place model files in `Core/Resources/Models/`
2. Add `ModelType` enum case in `ModelLibrary`
3. Register a factory in `ModelLibrary.makeLibrary()`: `register(.NewModel) { ObjModel("name") }` or `{ UsdModel("name", fileExtension: .USDZ) }` (built lazily on first access)
4. Access via `Assets.Models[.NewModel]`

### Adding New Player-Selectable Aircraft
1. Add the `AircraftType` case (rawValue is the display name in the picker)
2. Handle it in `FlightboxWithPhysics.applyAircraftSwap`'s switch (construct the Aircraft subclass)
3. Add its `AircraftThumbnailSpec.spec(for:)` entry — model name/extension must mirror `ModelLibrary.makeLibrary()`; tune the uprighting rotations visually and bump `ThumbnailCameraConfig.specVersion` when changing pose constants
4. Override `cameraOffset` on the Aircraft subclass if the default `[0, 10, -20]` doesn't frame it well

### Adding New Scenes
1. Create `GameScene` subclass
2. Override `buildScene()` to add objects, cameras, lights
3. Add `SceneType` enum case
4. Register in `SceneManager.SetScene()` switch

### Adding New Renderers
1. Create renderer class extending `Renderer`
2. Conform to needed protocols (`ShadowRendering`, `ParticleRendering`, `TiledGBufferRendering`, `LateDrawablePresenting`, etc.)
3. Add `RendererType` enum case
4. Register in `Engine.InitRenderer()` switch

## Testing

Two frameworks coexist:
- **XCTest**: `NodeTests`, `RendererTests` (unchanged legacy suites)
- **Swift Testing** (Apple's `@Test` framework, requires Xcode 26.2+): `Math/` (MathTests, MathUtilsTests, TransformTests), `Utils/` (TFSCacheTests, TFSLockTests, MDLMaterialSemanticTests, TimeItTests, ValueCurveTests, SymmetricSigmoidCurveTests), `AssetPipeline/` (MaterialTextureTransformTests, TextureLoaderOptionsTests, SingleMeshVertexMetadataTests, AircraftThumbnailSpecTests, AircraftThumbnailRenderTests), `Cameras/` (AttachedCameraTests), `GameObjects/` (AircraftTypeTests, GameObjectTypeTests), `Managers/` (SceneManagerRegisterTests, SceneManagerUnregisterTests), `Physics/` (RigidBodyTests, PhysicsSolverTests, PhysicsWorldSmokeTests), `Scenes/` (AircraftSwapTests, PendingSceneResetTests), `Shadows/` (ShadowCameraTests, ShadowCascadeFittingTests). Shared helpers in `TestSupport/` (`ApproxEqual.swift` for Float/SIMD/matrix tolerance comparisons; `Finite.swift` for NaN/Inf checks on SIMD vectors/matrices; `TestTags.swift` for `.math`, `.utils`, `.concurrency`, `.assetPipeline`, `.physics`, `.gameObjects`, `.scenes` filtering). Concurrency tests use `.timeLimit(.minutes(1))` to fail fast on lock leakage.

CI: `.github/workflows/test_macOS.yml` runs `xcodebuild test` on pushes to `main` and on PRs targeting `main` (macos-26 runner, Xcode 26.2), with `-parallel-testing-enabled NO` — serial execution avoids MTKView/CAMetalLayer drawable deadlocks in the app-hosted suite. Output via `xcbeautify --renderer github-actions`; `TestResults.xcresult` uploaded as artifact only on failure. `macOS.yml` is a separate build-only workflow on pushes to `main`.

## Debugging

- **'C' key**: Toggle debug/attached camera. Debug: WASD + mouselook. Attached: follows aircraft
- **'Y' key**: Toggle stats display (FPS + active renderer)
- **'H' key** (macOS; menu toggle on both platforms): Toggle Apple's Metal Performance HUD
- **ESC**: Toggle menu (pauses the game while open)
- **Cmd+R**: Reset scene (deferred to the update thread via `PendingSceneReset`; applies on the next unpaused tick)
- **Xcode GPU Frame Capture**: Detailed GPU analysis
- **Xcode Debug Navigator**: Memory usage monitoring
- All textures are labeled for GPU debugger identification
