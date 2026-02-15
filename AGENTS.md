# ToyFlightSimulator Agent Guide

## Scope
- Engine is Swift + Metal, shared across macOS/iOS/tvOS under `ToyFlightSimulator Shared/`.
- Main active code is in `Shared/`; platform folders mostly host SwiftUI/UIKit/AppKit wrappers.
- Primary runtime today: `Preferences.StartingSceneType = .FlightboxWithTerrain`; wrappers default renderer to `.TiledMSAATessellated`.

## Source Map
- `Core/`: Engine bootstrap, preferences, thread loop, timekeeping, input devices.
- `Display/`: renderer classes + reusable pass-encoding protocol mixins.
- `Graphics/`: shader function registry, pipeline/depth/sampler libraries, GBuffer helpers, `.metal` shaders.
- `Assets/`: model/mesh/material loading, texture cache, static asset libraries.
- `GameObjects/`: scene-graph nodes, aircraft/weapons, lights/cameras, particles, tessellated terrain.
- `Scenes/`: scene composition and per-scene update logic.
- `Animation/`: USD skeleton/skin/clip support + channel/layer animation system (F-35).
- `Physics/`: Euler/Verlet solvers, broad-phase SAP, Hecker collision response.
- `Managers/`: global orchestration (`SceneManager`, `DrawManager`, `InputManager`, etc.).
- `ToyFlightSimulatorTests/`: unit tests for `Node` and `Renderer`.

## Runtime Flow (Critical)
1. Platform wrapper calls `Engine.Start(rendererType:)`.
2. Engine starts `UpdateThread` + `AudioThread`, creates renderer, wires `updateSemaphore`.
3. Wrapper builds `GameView`, assigns `Engine.MetalView`, then `SceneManager.SetScene(...)`.
4. Renderers call `render { ... }` each frame.
5. `Renderer.render` signals update semaphore before and after render work (can trigger 2 scene updates per frame).
6. `UpdateThread` waits semaphore, runs `SceneManager.Update(deltaTime:)`, then increments game stats.

## Scene Graph + Registration
- `Node` is transform hierarchy root (position/rotation/scale + parent matrix propagation).
- `GameObject` extends `Node`, implements `PhysicsEntity` and carries `ModelConstants`.
- `GameScene.addChild` recursively registers new `GameObject`s into `SceneManager` buckets.
- `SceneManager.Register` routes by type:
  - sky objects, lights, lines, particles, tessellatables, icosahedrons, submesh objects, standard opaque/transparent models.
- If you bypass `GameScene.addChild`, object may exist but not render/update in manager-driven passes.

## Rendering Architecture
- Base class: `Renderer` (`MTKViewDelegate`), subclasses per `RendererType`.
- Implemented renderers:
  - `OITRenderer`
  - `SinglePassDeferredLightingRenderer`
  - `TiledDeferredRenderer`
  - `TiledMultisampleRenderer`
  - `TiledMSAATessellatedRenderer`
- Stub: `ForwardPlusTileShadingRenderer` (not implemented).
- Shared pass helpers live in `Display/Protocols/*`:
  - `RenderPassEncoding`, `ComputePassEncoding`, `ShadowRendering`, `ParticleRendering`, `TessellationRendering`, `BaseRendering`.
- `RenderState` tracks current/previous pipeline state globally (used by animation PSO switching hack).

## Draw Path
- `DrawManager` consumes `SceneManager.GetUniformsData()`/`GetTransparentUniformsData()`.
- Uniforms are copied into a freshly allocated `MTLBuffer` in draw calls (known non-optimized path).
- Animation skinning path:
  - if `mesh.skin?.jointMatrixPaletteBuffer` exists, `DrawManager.SetupAnimation` binds joint buffer and switches PSO to animated variant.
- Transparency sources:
  - object-level alpha (`modelConstants.objectColor.w < 1`) and/or material opacity textures/values.

## Graphics/Shader Conventions
- Add/rename shader functions in `.metal` + register in `ShaderLibrary` (`ShaderType` enum).
- Add new render pipeline in:
  - `RenderPipelineStateType` enum
  - concrete pipeline struct in `Graphics/Libraries/Pipelines/Render/*`
  - `RenderPipelineStateLibrary.makeLibrary()`.
- Add compute pipeline in:
  - `ComputePipelineStateType`
  - concrete compute pipeline struct
  - `ComputePipelineStateLibrary`.
- Shared CPU/GPU structs and index enums are in `Graphics/Shaders/TFSCommon.h`.

## Assets + Models
- Global singleton-style libraries: `Assets.Meshes`, `Assets.SingleSMMeshes`, `Assets.Textures`, `Assets.Models`.
- `ModelLibrary` eagerly instantiates many models (OBJ/USD + extracted F-18 submesh models).
- `TextureLoader` uses thread-safe caches keyed by string/url/MDL texture.
- `UsdModel` loads skeletons/skins/clips, maps mesh->skeleton, supports basis transforms, initializes pose at animation end by default.

## Animation Patterns
- Two systems coexist:
  - Legacy F-18 manual submesh control (`F18.swift`).
  - USD skeletal/channel system (`AnimationLayerSystem`, `BinaryAnimationChannel`, `ContinuousAnimationChannel`).
- `AnimationLayerSystem` sets `UsdModel.hasExternalAnimator = true`.
- F-35 path:
  - `F35` creates `F35Animator`.
  - `F35Animator` registers channel sets from `F35AnimationConfig`.
  - `ToggleGear` routes to animator, then animator updates channels/poses each frame.

## Physics Patterns
- `PhysicsWorld` modes: `.NaiveEuler`, `.HeckerVerlet`.
- Broad-phase (`BroadPhaseCollisionDetector`) is sweep-and-prune on X, enabled by `useBroadPhase`.
- Narrow phase and response via `HeckerCollisionResponse`.
- Gravity constant is currently `-(9.8 * 9.8)` (intentionally/non-physically strong).

## Input System
- `InputManager` is command-based:
  - discrete commands (`FireMissileAIM9`, `ToggleGear`, etc.)
  - continuous commands (`MoveFwd`, `Pitch`, `Roll`, `Yaw`).
- Sources merged: keyboard + game controller + macOS HOTAS (joystick/throttle) + iOS motion + touch controls.
- Debounced handlers (`HasDiscreteCommandDebounced`, `HandleMouseClickDebounced`) are used heavily in update loops.

## High-Risk Areas / Gotchas
- Many globals are `nonisolated(unsafe)`; thread safety is selective (locks exist, but not everywhere).
- Scene/model registries are mutable global state in `SceneManager`; reset/teardown order matters.
- `tvOS/GameViewController.swift` uses an outdated renderer initializer and is likely stale.
- `UpdateThread` is an infinite loop; pausing is done via `SceneManager.Paused` + `Engine.PauseView`.
- Several files contain TODO/hack comments documenting known rendering/animation limitations; avoid “cleanups” without runtime verification.

## Safe Extension Recipes
- New game object:
  - subclass `GameObject` (or `Aircraft`/`ParticleEmitterObject`).
  - override `doUpdate()` only.
  - add via scene `addChild(...)` so registration happens.
- New scene:
  - subclass `GameScene`, implement `buildScene()`.
  - add case to `SceneType` and switch in `SceneManager.SetScene`.
- New renderer:
  - subclass `Renderer`, implement `draw(in:)` + `mtkView(_:drawableSizeWillChange:)`.
  - add enum case + engine switch in `Engine.InitRenderer`.

## Build/Test Commands
```bash
# macOS debug build
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# macOS tests
xcodebuild test -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# iOS simulator build
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator iOS" -sdk iphonesimulator -configuration Debug
```

## Style
- Swift style is existing-project style (no formatter config): 4-space indentation, PascalCase types, camelCase members.
- Keep filenames aligned to primary type.
