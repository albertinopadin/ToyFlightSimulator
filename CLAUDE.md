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
ToyFlightSimulator Shared/     # Cross-platform engine (~175 Swift files, 22 Metal shaders)
  Animation/                   # Skeletal animation, channels, layer system
    Animators/                 # AnimationController, AircraftAnimator base, F22Animator, F35Animator
    Configs/                   # F22AnimationConfig, F35AnimationConfig
    Layers/                    # AnimationChannel protocol, Binary/Continuous channels, AnimationLayer, masks
  AssetPipeline/               # Asset import + management (renamed from Assets/)
    Assets.xcassets            # Image/texture assets
    Libraries/Meshes/          # MeshLibrary, procedural meshes
    Libraries/Textures/        # TextureLoader (singleton cache), TextureLibrary
    Libraries/Models/          # ModelLibrary (OBJ/USDZ loading)
    Mesh.swift, Material.swift, ObjModel.swift, UsdModel.swift, etc.
  Audio/                       # TFSAudioSystem (AVAudioEngine wrapper)
  Core/
    Input/                     # Keyboard, Mouse, Joystick (HOTAS), Controller, MotionDevice
    Threads/                   # UpdateThread (game logic), AudioThread
    Resources/Models/          # 3D model files (F16, F18, F22, F35, Temple, etc.)
  Display/                     # Renderers and protocols
    Protocols/                 # BaseRendering, ShadowRendering, ParticleRendering,
                               # TessellationRendering, TiledGBufferRendering, LateDrawablePresenting
  GameObjects/                 # Node → GameObject hierarchy, Aircraft, Weapons, Cameras, Particles
  Graphics/
    Shaders/                   # All .metal files + TFSCommon.h shared definitions
    Libraries/Pipelines/       # Render/Compute pipeline states (~37 render pipeline cases + compute)
  Managers/                    # SceneManager, CameraManager, LightManager, DrawManager, AudioManager
  Math/                        # Math utilities (Transform.* is canonical, Math/MathUtils have niche helpers)
  Physics/                     # PhysicsWorld, solvers, collision detection
  Scenes/                      # GameScene subclasses (Flightbox, FlightboxWithPhysics, Sandbox, etc.)
  Utils/                       # TFSCache, TFSLock, ModelIO extensions
ToyFlightSimulator macOS/
  Views/                       # MacMetalViewWrapper, MacGameUIView, GameStats, TFSMenu (SwiftUI)
  AppDelegate.swift, GameViewController.swift
ToyFlightSimulator iOS/        # SwiftUI app entry, touch controls (virtual joystick/throttle)
ToyFlightSimulator tvOS/       # tvOS target
ToyFlightSimulatorTests/       # XCTest: NodeTests, RendererTests
                               # Swift Testing: Math/, Utils/, AssetPipeline/, TestSupport/
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
- **Node**: Base class with transform hierarchy (position, rotation, scale). `modelMatrix = parentModelMatrix * localMatrix`. Children updated recursively via `update()` → `doUpdate()`.
- **GameObject**: Extends Node. Has `Model` (meshes + materials), `ModelConstants` (shader uniforms), implements `PhysicsEntity` protocol. `Hashable` for collection use.
- **GameScene**: Root node. `buildScene()` overridden by subclasses. `addChild()` auto-registers with SceneManager. Has `addCamera()`, `addLight()` helpers.

### Scenes (Scenes/)
`GameScene` subclasses: `FlightboxScene`, `FlightboxWithTerrain`, `FlightboxWithPhysics`, `FreeCamFlightboxScene`, `SandboxScene`, `BallPhysicsScene`, `PhysicsStressTestScene`. Default starting scene set in `Preferences.StartingSceneType`.

`GameScene` base class provides `addGround(color:restitution:rotationZ:scale:)` and `setupDefaultSky()` helpers (OIT → SkySphere, SinglePassDeferred → SkyBox) so subclasses don't reimplement common boilerplate.

### Coordinate Conventions
**Left-handed Metal-native** throughout. Camera looks down +Z (forward); projection maps clip-space depth to [0,1] (`Transform.perspectiveProjection` is the single source of truth). `Node.getFwdVector()` returns +column2 directly. Aircraft pitch/roll/yaw inputs are negated to keep pilot-perspective rotation directions stable. Model basis transforms with det<0 (e.g., Sketchfab F-22's `transformYMinusZXToXYZ`) are reindexed at import (`Mesh.reverseTriangleWinding()`) so the global `setFrontFacing(.clockwise) + setCullMode(.back)` works uniformly.

### SceneManager (Managers/SceneManager.swift)
Batches `ContiguousArray<GameObject>` per Model for instanced rendering. Separates opaque/transparent submeshes. Triple-buffered `RingBufferRegion` snapshots (offset, count, meshDatas) per frame. The update thread calls `writeFrameSnapshot(frameIndex:)` which writes ModelConstants directly into the per-frame ring buffer slot via `DrawManager.writeModelConstants` — no intermediate dict/array allocations on the render hot path. Render thread reads regions via `getOpaqueSnapshot/getTransparentSnapshot/getSkySnapshot`. Transparent objects cache their MeshData arrays at registration time. Thread-safe via `OSAllocatedUnfairLock`.

### Rendering System

**6 Renderer Types** (`RendererType` enum, switchable at runtime via menu):

| Renderer | Shadow | GBuffer | MSAA | Tessellation | Particles |
|----------|--------|---------|------|--------------|-----------|
| SinglePassDeferredLighting | 8K depth32F | 3 (albedo+spec, normal+shadow, depth) memoryless | No | No | No |
| TiledDeferred | 8K depth32F | 4 (albedo, normal 16F, position 16F, lighting) memoryless | No | No | Yes |
| TiledDeferredMSAA | 8K depth32F 4x | 4 targets, 4x MSAA | 4x | No | Yes |
| TiledMSAATessellated | 8K depth32F 4x | 4 targets, 4x MSAA | 4x | Yes | Yes |
| OrderIndependentTransparency | None | None (image blocks) | No | No | No |
| ForwardPlusTileShading | — | — | — | — | — (stub) |

**Render pass flow** (typical deferred): Shadow map pass → GBuffer generation → Directional lighting → Transparency → Point light volumes (stencil-masked icosahedrons) → Skybox → (Particles if supported) → Late composite into drawable

**Key rendering protocols** (Display/Protocols/): `RenderPassEncoding`, `ComputePassEncoding`, `ShadowRendering`, `ParticleRendering`, `TessellationRendering`, `TiledGBufferRendering` (default `setGBufferTextures`/`setDepthAndStencilTextures` for the three tiled deferred renderers), `LateDrawablePresenting` (drawable acquisition + composite). Renderers compose these via protocol conformance.

**Pipeline states**: ~37 render pipeline cases (+ compute) in `RenderPipelineStateLibrary`, created via factory pattern. Each renderer type has its own set of pipelines defined in dedicated files (SinglePassDeferredPipeline, TiledDeferredPipeline, etc.). `RenderPipelineState` protocol extension provides `enableBlending(...)` (alpha) and `enableAdditiveBlending(...)` (point-light volume path).

**Late drawable acquisition** (SinglePassDeferred, TiledDeferred, TiledMultisample, TiledMSAATessellated): per Apple's "acquire late, release early" guidance, each frame uses three command buffers — (1) Shadow CB, (2) Offscreen CB writing GBuffer/lighting/transparency/MSAA-resolve into an app-owned `lightingResolveTexture`, (3) Late CB that finally calls `view.currentDrawable`, runs a full-screen composite, and presents. Shrinks drawable hold window from milliseconds to tens of µs and reduces nextDrawable() stalls.

**Frame pacing**: `inFlightSemaphore` with max 3 frames in flight. Render and update threads synchronize via `updateSemaphore` (render→update wakeup) and `updateDoneSemaphore` (update→render handshake): render signals the update thread at the START of the frame with the next ring-buffer slot index, waits for the update to finish, then encodes — this keeps ring-buffer ModelConstants and `_sceneConstants` (viewMatrix, cameraPosition, light data) consistent within the same frame, eliminating the camera/aircraft desync that occurred when reading data from different update generations.

### Shader System (Graphics/Shaders/)
22 Metal files. Shared definitions in `TFSCommon.h` (buffer indices, vertex attributes, texture indices, render target indices, struct definitions for ModelConstants, SceneConstants, MaterialProperties, LightData, Particle, Terrain). `ShaderDefinitions.h` has GBuffer output struct with raster order groups.

**Pixel formats** (Preferences.swift): `bgra8Unorm_srgb` (main), `depth32Float` (depth), `depth32Float_stencil8` (depth+stencil).

### Asset System (AssetPipeline/)
**Assets** singleton: `Assets.Meshes` (MeshLibrary), `Assets.Textures` (TextureLibrary), `Assets.Models` (ModelLibrary), `Assets.SingleSMMeshes` (SingleSubmeshMeshLibrary). All use generic `Library<Key, Value>` base with lazy init.

**TextureLoader**: Singleton MTKTextureLoader with 3-level TFSCache (by String, URL, MDLTexture). Auto-generates mipmaps, uses `.private` storage mode. Thread-safe. Default texture origin is `.bottomLeft` consistently across entry points.

**Model loading**: `ObjModel` (OBJ+MTL via ModelIO; accepts a basis transform), `UsdModel` (USDZ with skeleton/animation/skin support). Both use custom vertex descriptor (position, color, texcoord, normal, tangent, bitangent, joints, jointWeights). Tangent bases generated on the MDL mesh before the MTK mesh is created.

**Material UV transforms**: `MDLTextureSampler.transform` is captured per slot (baseColor, normal, specular, opacity) at import time, stored as `matrix_float3x3` in `MaterialTextureTransforms` and bound at fragment buffer index 12 (`TFSBufferIndexMaterialTextureTransforms`). A `hasTextureTransforms` bool gates the UV `mat3` multiply so the identity path is branch-free. Mirrors glTF KHR_texture_transform / USD UsdTransform2d semantics.

**Material color extraction**: `Material.populateMaterial()` handles `.color`, `.float3`, `.float4` for the `.baseColor` semantic only — earlier code only handled `.color`, which silently dropped USD float3 base colors and caused the default init color to bleed into untextured submeshes (F22 canopy/HUD glass).

**SingleSubmeshMeshLibrary**: Extracts individual submeshes from parent models (F18 weapons, control surfaces, fuel tanks) without duplicating vertex data.

**Procedural meshes**: Triangle, Quad, Cube, Sphere, Capsule, Plane, Skybox, SkySphere, Icosahedron.

### Animation System (Animation/)
**AnimationController** protocol with playback state management. **AnimationLayerSystem** manages layers and channels with dirty-flag optimization.

**Channel types** (individual animated elements):
- `BinaryAnimationChannel`: Two-state (landing gear up/down). States: inactive → activating → active → deactivating. Progress-based smooth transitions.
- `ContinuousAnimationChannel`: Variable-position (flaps, control surfaces). Value range with `transitionSpeed`.

**AnimationLayer**: Groups related channels that animate together to form a discrete animation (e.g., all the channels needed to extend the landing gear). **AnimationMask** for selective joint targeting. Skeleton/skin palette updates per channel. Layer IDs are typed via `enum AnimationLayerID: String` (cases: `landingGear`, `flaperon`, `aileron`, `horizontalStabilizer`, `rudder`) defined once in `AircraftAnimator.swift`.

**Skeleton conjugation**: `Skeleton.evaluateWorldPoses` and `TransformComponent` use `B^-1 * J * B` (not `B * J * B^-1`). Mesh transform is row-vector (`v_engine = v*B`); shader skins as column-vector (`J*v`). Matters for proper rotations even though it's a no-op for symmetric/self-inverse axis-swap basis matrices.

**Aircraft animators**: `AircraftAnimator` base → `F35Animator`, `F22Animator`. `Aircraft` base provides `setupAnimator<A: AircraftAnimator>(_ make: (UsdModel) -> A)` (handles UsdModel cast + warning) and a default `doUpdate()` that runs gear-toggle input and `animator?.update(deltaTime:)`. Subclasses only override `doUpdate` if they need procedural per-frame logic beyond the animator (e.g., `F22_CGTrader` for ailerons/flaperons/horizontal stabs/rudders). `Aircraft.isGearDown` returns `animator?.isGearDown ?? true`.

### Physics (Physics/)
**PhysicsWorld**: Manages entities, runs in UpdateThread. **Solvers**: `EulerSolver` (explicit), `VerletSolver` (implicit). **Collision**: `BroadPhaseCollisionDetector` (sweep-and-prune on X-axis with frame coherence), `HeckerCollisionResponse` (sphere-sphere, sphere-plane). **PhysicsEntity** protocol on GameObject (mass, velocity, acceleration, restitution, AABB).

### Input (Core/Input/)
Platform-abstracted via `InputManager` singleton. **macOS**: Keyboard (256-key state array), Mouse (buttons + delta + scroll), GameController (GCController), Joystick/Throttle (Thrustmaster Warthog HOTAS via IOKit HID). **iOS**: CoreMotion (attitude at 60Hz), TFSTouchJoystick/TFSTouchThrottle. Commands: `DiscreteCommands` (fire, toggle gear/flaps), `ContinuousCommands` (pitch, roll, yaw, move). Debouncing for discrete commands.

### Camera System (GameObjects/Cameras/)
`Camera` base (FOV, near/far, projection matrix from `Transform.perspectiveProjection`; view = `modelMatrix.inverse`). `DebugCamera` (WASD + mouselook). `AttachedCamera` (parents to node, follows aircraft; default offset `[0, 2, -4]` since +Z is forward; overrides `update()` to recompute view matrix when parent moves via `worldMatrixDirty`). `CameraManager.CurrentCamera` is now optional (`Camera?`) — guarded everywhere instead of force-unwrapped, so scene transitions and pre-scene-set states no longer crash. `CameraManager.Update()` skips parented cameras (they're updated through scene-graph traversal — prevents double `doUpdate`). Toggle with 'C' key.

### Lighting (GameObjects/LightObject.swift, Managers/LightManager.swift)
`LightObject` extends GameObject. Types: Directional, Point. Shadow matrices computed per frame. `Sun` subclass for main directional light. `LightManager` singleton (thread-safe) provides light data arrays to shaders. Point lights rendered as icosahedron instances with stencil masking.

### Particles (GameObjects/Particles/)
`ParticleEmitter` descriptor-based (birth rate, life, speed, scale, color). Predefined: Fire (1200 particles, upward), Afterburner (1200, forward). Compute shader updates positions, render stage draws with appropriate pipeline.

### Threading
- **Main Thread**: Rendering (MTKView delegate), UI, input capture
- **UpdateThread**: Game logic + physics. Wakes on `updateSemaphore`, calls `SceneManager.writeFrameSnapshot(frameIndex:)` to write ModelConstants directly into the next ring-buffer slot, then signals `updateDoneSemaphore`. Delta time from `DispatchTime.now().uptimeNanoseconds`.
- **AudioThread**: Lazy start after scene built. AVAudioEngine for MP3 playback
- **Synchronization**: `OSAllocatedUnfairLock` (managers, caches, input state), `DispatchSemaphore` (`inFlightSemaphore` for max 3 frames in flight; `updateSemaphore` + `updateDoneSemaphore` for render↔update handshake within a frame)

### Platform Differences
- **macOS**: NSViewRepresentable bridge (`MacMetalViewWrapper` in `Views/`), SwiftUI menu for renderer selection (`TFSMenu`), keyboard/mouse/HOTAS input, `GameViewController` captures key events. SwiftUI views (`MacGameUIView`, `GameStats`) live in `ToyFlightSimulator macOS/Views/`.
- **iOS**: UIViewRepresentable bridge (`IOSMetalViewWrapper`), hardcoded `TiledMSAATessellated` renderer, touch controls overlay, CoreMotion input

## Key Development Patterns

### Adding New Game Objects
1. Extend `GameObject` (or `Aircraft` for vehicles)
2. Override `doUpdate()` for per-frame logic
3. Add to scene via `addChild()` in a `GameScene.buildScene()` override
4. SceneManager auto-registers for batched rendering

### Adding New Shaders
1. Add Metal functions to appropriate .metal file (or new file)
2. Add enum case to `RenderPipelineStateType`
3. Create pipeline state struct in relevant pipeline library file
4. Register in `RenderPipelineStateLibrary.makeLibrary()`
5. Use in renderer via `setRenderPipelineState(encoder, state: .NewType)`

### Adding New Models
1. Place model files in `Core/Resources/Models/`
2. Add `ModelType` enum case in `ModelLibrary`
3. Initialize as `ObjModel("name")` or `UsdModel("name", fileExtension: .USDZ)` in `ModelLibrary.makeLibrary()`
4. Access via `Assets.Models[.NewModel]`

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
- **Swift Testing** (Apple's `@Test` framework, requires Xcode 26.2+): `Math/` (MathTests, MathUtilsTests, TransformTests), `Utils/` (TFSCacheTests, TFSLockTests, MDLMaterialSemanticTests, TimeItTests), `AssetPipeline/` (MaterialTextureTransformTests). Shared helpers in `TestSupport/` (`ApproxEqual.swift` for Float/SIMD/matrix tolerance comparisons; `TestTags.swift` for `.math`, `.utils`, `.concurrency` filtering). Concurrency tests use `.timeLimit(.minutes(1))` to fail fast on lock leakage.

CI: `.github/workflows/test_macOS.yml` runs `xcodebuild test` on every push to `main` (macos-26 runner, Xcode 26.2). Output via `xcbeautify --renderer github-actions`; `TestResults.xcresult` uploaded as artifact only on failure.

## Debugging

- **'C' key**: Toggle debug/attached camera. Debug: WASD + mouselook. Attached: follows aircraft
- **'Y' key**: Toggle stats display (FPS)
- **ESC**: Toggle menu
- **Cmd+R**: Reset scene
- **Xcode GPU Frame Capture**: Detailed GPU analysis
- **Xcode Debug Navigator**: Memory usage monitoring
- All textures are labeled for GPU debugger identification
