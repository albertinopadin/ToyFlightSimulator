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
ToyFlightSimulator Shared/     # Cross-platform engine (168 Swift files, 22 Metal shaders)
  Animation/                   # Skeletal animation, channels, layer system
    Aircraft/                  # Aircraft-specific animators (F35, etc.)
    Layers/                    # AnimationChannel protocol, Binary/Continuous channels, AnimationLayer, masks
  Assets/                      # Asset management and libraries
    Libraries/Meshes/          # MeshLibrary, procedural meshes
    Libraries/Textures/        # TextureLoader (singleton cache), TextureLibrary
    Libraries/Models/          # ModelLibrary (OBJ/USDZ loading)
  Audio/                       # TFSAudioSystem (AVAudioEngine wrapper)
  Core/
    Input/                     # Keyboard, Mouse, Joystick (HOTAS), Controller, MotionDevice
    Threads/                   # UpdateThread (game logic), AudioThread
    Resources/Models/          # 3D model files (F16, F18, F35, Temple, etc.)
  Display/                     # Renderers and protocols
    Protocols/                 # BaseRendering, ShadowRendering, ParticleRendering, etc.
  GameObjects/                 # Node → GameObject hierarchy, Aircraft, Weapons, Cameras, Particles
  Graphics/
    Shaders/                   # All .metal files + TFSCommon.h shared definitions
    Libraries/Pipelines/       # Render/Compute pipeline states (~62 pipeline types)
  Managers/                    # SceneManager, CameraManager, LightManager, AudioManager
  Math/                        # Math utilities
  Physics/                     # PhysicsWorld, solvers, collision detection
  Scenes/                      # GameScene subclasses (Flightbox, Sandbox, etc.)
  Utils/                       # TFSCache, TFSLock, ModelIO extensions
ToyFlightSimulator macOS/      # AppDelegate, GameViewController, TFSMenu, SwiftUI wrappers
ToyFlightSimulator iOS/        # SwiftUI app entry, touch controls (virtual joystick/throttle)
ToyFlightSimulator tvOS/       # tvOS target
ToyFlightSimulatorTests/       # NodeTests, RendererTests
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
`GameScene` subclasses: `FlightboxScene`, `FlightboxWithTerrain`, `FreeCamFlightboxScene`, `SandboxScene`, `BallPhysicsScene`, `PhysicsStressTestScene`. Default starting scene set in `Preferences.StartingSceneType`.

### SceneManager (Managers/SceneManager.swift)
Batches GameObjects by Model type for instanced rendering. Separates opaque/transparent submeshes. Provides `GetUniformsData()` / `GetTransparentUniformsData()` for efficient draw call batching. Thread-safe via `OSAllocatedUnfairLock`.

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

**Render pass flow** (typical deferred): Shadow map pass → GBuffer generation → Directional lighting → Transparency → Point light volumes (stencil-masked icosahedrons) → Skybox → (Particles if supported)

**Key rendering protocols** (Display/Protocols/): `RenderPassEncoding`, `ComputePassEncoding`, `ShadowRendering`, `ParticleRendering`, `TessellationRendering`. Renderers compose these via protocol conformance.

**Pipeline states**: ~62 types in `RenderPipelineStateLibrary` enum, created via factory pattern. Each renderer type has its own set of pipelines defined in dedicated files (SinglePassDeferredPipeline, TiledDeferredPipeline, etc.).

**Frame pacing**: `inFlightSemaphore` with max 3 frames in flight. Command buffer completion handler signals semaphore.

### Shader System (Graphics/Shaders/)
22 Metal files. Shared definitions in `TFSCommon.h` (buffer indices, vertex attributes, texture indices, render target indices, struct definitions for ModelConstants, SceneConstants, MaterialProperties, LightData, Particle, Terrain). `ShaderDefinitions.h` has GBuffer output struct with raster order groups.

**Pixel formats** (Preferences.swift): `bgra8Unorm_srgb` (main), `depth32Float` (depth), `depth32Float_stencil8` (depth+stencil).

### Asset System (Assets/)
**Assets** singleton: `Assets.Meshes` (MeshLibrary), `Assets.Textures` (TextureLibrary), `Assets.Models` (ModelLibrary), `Assets.SingleSMMeshes` (SingleSubmeshMeshLibrary). All use generic `Library<Key, Value>` base with lazy init.

**TextureLoader**: Singleton MTKTextureLoader with 3-level TFSCache (by String, URL, MDLTexture). Auto-generates mipmaps, uses `.private` storage mode. Thread-safe.

**Model loading**: `ObjModel` (OBJ+MTL via ModelIO), `UsdModel` (USDZ with skeleton/animation/skin support). Both use custom vertex descriptor (position, color, texcoord, normal, tangent, bitangent, joints, jointWeights). Supports basis transform for coordinate system conversion.

**SingleSubmeshMeshLibrary**: Extracts individual submeshes from parent models (F18 weapons, control surfaces, fuel tanks) without duplicating vertex data.

**Procedural meshes**: Triangle, Quad, Cube, Sphere, Capsule, Plane, Skybox, SkySphere, Icosahedron.

### Animation System (Animation/)
**AnimationController** protocol with playback state management. **AnimationLayerSystem** manages layers and channels with dirty-flag optimization.

**Channel types** (individual animated elements):
- `BinaryAnimationChannel`: Two-state (landing gear up/down). States: inactive → activating → active → deactivating. Progress-based smooth transitions.
- `ContinuousAnimationChannel`: Variable-position (flaps, control surfaces). Value range with `transitionSpeed`.

**AnimationLayer**: Groups related channels that animate together to form a discrete animation (e.g., all the channels needed to extend the landing gear). **AnimationMask** for selective joint targeting. Skeleton/skin palette updates per channel.

**Aircraft animators**: `AircraftAnimator` base → `F35Animator`. Tie into `Aircraft.isGearDown` property.

### Physics (Physics/)
**PhysicsWorld**: Manages entities, runs in UpdateThread. **Solvers**: `EulerSolver` (explicit), `VerletSolver` (implicit). **Collision**: `BroadPhaseCollisionDetector` (sweep-and-prune on X-axis with frame coherence), `HeckerCollisionResponse` (sphere-sphere, sphere-plane). **PhysicsEntity** protocol on GameObject (mass, velocity, acceleration, restitution, AABB).

### Input (Core/Input/)
Platform-abstracted via `InputManager` singleton. **macOS**: Keyboard (256-key state array), Mouse (buttons + delta + scroll), GameController (GCController), Joystick/Throttle (Thrustmaster Warthog HOTAS via IOKit HID). **iOS**: CoreMotion (attitude at 60Hz), TFSTouchJoystick/TFSTouchThrottle. Commands: `DiscreteCommands` (fire, toggle gear/flaps), `ContinuousCommands` (pitch, roll, yaw, move). Debouncing for discrete commands.

### Camera System (GameObjects/Cameras/)
`Camera` base (FOV, near/far, projection matrix). `DebugCamera` (WASD + mouselook). `AttachedCamera` (parents to node, follows aircraft). `CameraManager` singleton handles registration and switching. Toggle with 'C' key.

### Lighting (GameObjects/LightObject.swift, Managers/LightManager.swift)
`LightObject` extends GameObject. Types: Directional, Point. Shadow matrices computed per frame. `Sun` subclass for main directional light. `LightManager` singleton (thread-safe) provides light data arrays to shaders. Point lights rendered as icosahedron instances with stencil masking.

### Particles (GameObjects/Particles/)
`ParticleEmitter` descriptor-based (birth rate, life, speed, scale, color). Predefined: Fire (1200 particles, upward), Afterburner (1200, forward). Compute shader updates positions, render stage draws with appropriate pipeline.

### Threading
- **Main Thread**: Rendering (MTKView delegate), UI, input capture
- **UpdateThread**: Game logic + physics at semaphore-driven rate. Delta time from `DispatchTime.now().uptimeNanoseconds`
- **AudioThread**: Lazy start after scene built. AVAudioEngine for MP3 playback
- **Synchronization**: `OSAllocatedUnfairLock` (managers, caches, input state), `DispatchSemaphore` (render ↔ update sync, frame pacing)

### Platform Differences
- **macOS**: NSViewRepresentable bridge (`MacMetalViewWrapper`), SwiftUI menu for renderer selection, keyboard/mouse/HOTAS input, `GameViewController` captures key events
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
2. Conform to needed protocols (`ShadowRendering`, `ParticleRendering`, etc.)
3. Add `RendererType` enum case
4. Register in `Engine.InitRenderer()` switch

## Debugging

- **'C' key**: Toggle debug/attached camera. Debug: WASD + mouselook. Attached: follows aircraft
- **'Y' key**: Toggle stats display (FPS)
- **ESC**: Toggle menu
- **Cmd+R**: Reset scene
- **Xcode GPU Frame Capture**: Detailed GPU analysis
- **Xcode Debug Navigator**: Memory usage monitoring
- All textures are labeled for GPU debugger identification
