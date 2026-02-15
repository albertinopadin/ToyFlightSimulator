# ToyFlightSimulator

## Project Overview
**ToyFlightSimulator** is a custom flight simulator engine built from scratch using **Swift** and **Metal**. It targets macOS, iOS, and tvOS, sharing the majority of its codebase (~95%) via the `ToyFlightSimulator Shared` directory.

The project demonstrates advanced graphics techniques including **Tiled Deferred Lighting**, **Order Independent Transparency (OIT)**, **Tessellation**, **Shadow Mapping**, and **Skeletal Animation**.

## Architecture

### 1. Core Engine
*   **Entry Point**: `Engine.Start(rendererType:)` initializes the `Renderer`, `UpdateThread`, and `AudioThread`.
*   **Threading Model**:
    *   **Main Thread**: Handles Rendering (`MTKViewDelegate`), UI events, and Input capture.
    *   **Update Thread**: Runs the game loop (`SceneManager.Update`) and physics simulation at a target frame rate, synchronized via `DispatchSemaphore`.
    *   **Audio Thread**: Managed separately for `AVAudioEngine`.
*   **State Management**: `SceneManager` acts as the central repository for all active game objects, managing their lifecycle and grouping them for rendering.

### 2. Rendering Pipeline
The engine supports multiple rendering paths, switchable at runtime (on macOS):
*   **Tiled MSAA Tessellated**: The default high-fidelity renderer. Supports 4x MSAA, tessellated terrain, and particle effects.
*   **Tiled Deferred**: Efficient deferred shading with support for many lights.
*   **Single Pass Deferred**: Optimized for mobile (iOS) using Tile Memory.
*   **Order Independent Transparency (OIT)**: Uses image blocks for pixel-perfect transparency.

**Key Components**:
*   `Renderer` (Base Class): Implements `MTKViewDelegate`.
*   `Display/Protocols`: Mixins like `ShadowRendering`, `TessellationRendering` define pass capabilities.
*   `Graphics/Shaders`: Metal shader files. `TFSCommon.h` defines shared structs between Swift and MSL.

### 3. Scene Graph
*   **Node**: Base class handling `Transform` (position, rotation, scale) and hierarchical updates.
*   **GameObject**: Extends `Node`, adds `Model` (Mesh + Material) and `PhysicsEntity` conformance.
*   **Registration**: Objects added to a `GameScene` are automatically registered with `SceneManager` into buckets (e.g., `modelDatas`, `transparentObjectDatas`) for batched instanced rendering.

### 4. Animation & Physics
*   **Animation**: Hybrid system.
    *   **Legacy**: Manual submesh manipulation (e.g., F-18 control surfaces).
    *   **Skeletal**: USD-based skinning and channel animation (e.g., F-35 landing gear).
*   **Physics**: Custom engine with two solvers:
    *   `NaiveEuler`: Simple integration.
    *   `HeckerVerlet`: Verlet integration with impulse-based collision response (`HeckerCollisionResponse`).

## Key Files & Directories

### Shared Core (`ToyFlightSimulator Shared/`)
| Directory | Description |
| :--- | :--- |
| **Core/** | `Engine.swift` (bootstrap), `Input/` (Platform-agnostic input), `Threads/`. |
| **Managers/** | `SceneManager.swift` (Global object registry), `LightManager`, `CameraManager`. |
| **Display/** | `Renderer.swift` and concrete implementations (`TiledMSAATessellatedRenderer.swift`, etc.). |
| **GameObjects/** | Entities like `Aircraft`, `Missile`, `Terrain`, `Particles`. |
| **Graphics/** | `Shaders/` (Metal files), `Libraries/` (Pipeline State Objects). |
| **Assets/** | Singleton loaders (`TextureLoader`, `ModelLibrary`) and caching logic. |
| **Animation/** | Skeletal animation system, `AnimationLayerSystem`. |
| **Physics/** | Collision detection (`BroadPhase`) and resolution solvers. |

### Platform-Specific
*   **macOS**: `ToyFlightSimulator macOS/` - App Delegate, Menu, Keyboard/Mouse/HOTAS input.
*   **iOS**: `ToyFlightSimulator iOS/` - Touch controls, CoreMotion integration.

## Development Workflows

### Building and Running
The project uses `xcodebuild`.
```bash
# macOS Debug Build
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# iOS Simulator Build
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator iOS" -sdk iphonesimulator -configuration Debug
```

### Adding a New Game Object
1.  **Create Class**: Inherit from `GameObject` (or `Aircraft` / `Structure`).
2.  **Override Update**: Implement `override func doUpdate()` for per-frame logic.
3.  **Add to Scene**: In your `GameScene` subclass (e.g., `FlightboxScene.swift`), call `addChild(yourObject)`.
    *   *Note*: `SceneManager` will automatically detect the object type (Opaque, Transparent, Light, etc.) and batch it.

### Modifying Shaders
1.  **Edit Metal**: Modify files in `Graphics/Shaders/`.
2.  **Update Structs**: If changing data layout, update **both** `TFSCommon.h` (C-style struct) and the corresponding Swift struct (usually `ModelConstants` or similar).
3.  **Rebuild**: Metal shaders are compiled at build time.

## Gotchas & Guidelines
*   **Global State**: `SceneManager`, `Assets`, and `InputManager` rely heavily on global singleton patterns and `nonisolated(unsafe)` variables. Be careful with initialization order.
*   **Thread Safety**:
    *   The **Update Thread** and **Render Thread** run concurrently.
    *   Use `OSAllocatedUnfairLock` (present in Managers) when accessing shared data like `UniformsData`.
*   **Coordinate System**: Left-handed, Y-up (Standard Metal).
*   **Performance**: The engine relies on **Instanced Rendering**. Adding unique `Model` objects prevents batching; prefer reusing Models and varying `ModelConstants` (Transform/Color) where possible.
