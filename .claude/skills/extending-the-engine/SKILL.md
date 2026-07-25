---
name: extending-the-engine
description: Step-by-step recipes for adding new game objects, shaders, models, player-selectable aircraft, scenes, or renderers to the ToyFlightSimulator engine. Use when creating a new GameObject/Aircraft subclass, a Metal shader plus its pipeline state, a model file registration, an AircraftType case, a GameScene subclass, or a Renderer subclass.
---

# Extending the engine

Registration recipes for the ToyFlightSimulator Metal engine. Each list is the full set of
touchpoints — missing one typically compiles but silently does nothing at runtime.

## Adding New Game Objects

1. Extend `GameObject` (or `Aircraft` for vehicles)
2. Override `doUpdate()` for per-frame logic
3. Add to scene via `addChild()` in a `GameScene.buildScene()` override
4. SceneManager auto-registers for batched rendering (base `objectType` handles opaque/transparent/tessellatable; override it — and extend `GameObjectType` + both `add`/`remove` switches — only for a new side collection)
5. For physics: construct a `SphereRigidBody`/`PlaneRigidBody` (self-attaches to the GameObject) and register it with the scene's `PhysicsWorld` via `addEntity()`
6. Runtime despawns must use `removeFromScene()`, not bare `parent?.removeChild(self)` (see Scene Graph in CLAUDE.md)

## Adding New Shaders

1. Add Metal functions to appropriate .metal file (or new file)
2. Add enum case to `RenderPipelineStateType`
3. Create pipeline state struct in relevant pipeline library file
4. Register in `RenderPipelineStateLibrary.makeLibrary()`
5. Use in renderer via `setRenderPipelineState(encoder, state: .NewType)` (convenience sugar over the raw encoder bind) and pass the stage's pipeline type to the mesh-draw entry points — `DrawManager.DrawOpaque/DrawTransparent/DrawShadows` take `psoType:`, from which `SetupAnimation` derives the skinned-mesh animated PSO via `animatedVariant` and restores the pass PSO at non-skinned meshes and loop boundaries (no global pipeline tracking; keep the bind and the draw call reading one local constant)

## Adding New Models

1. Place model files in `Core/Resources/Models/`
2. Add `ModelType` enum case in `ModelLibrary`
3. Register a factory in `ModelLibrary.makeLibrary()`: `register(.NewModel) { ObjModel("name") }` or `{ UsdModel("name", fileExtension: .USDZ) }` (built lazily on first access)
4. Access via `Assets.Models[.NewModel]`

## Adding New Player-Selectable Aircraft

1. Add the `AircraftType` case (rawValue is the display name in the picker)
2. Handle it in `FlightboxWithPhysics.applyAircraftSwap`'s switch (construct the Aircraft subclass)
3. Add its `AircraftThumbnailSpec.spec(for:)` entry — model name/extension must mirror `ModelLibrary.makeLibrary()`; tune the uprighting rotations visually and bump `ThumbnailCameraConfig.specVersion` when changing pose constants
4. Override `cameraOffset` on the Aircraft subclass if the default `[0, 10, -20]` doesn't frame it well

## Adding New Scenes

1. Create `GameScene` subclass
2. Override `buildScene()` to add objects, cameras, lights
3. Add `SceneType` enum case
4. Register in `SceneManager.SetScene()` switch

## Adding New Renderers

1. Create renderer class extending `Renderer`
2. Conform to needed protocols (`ShadowRendering`, `ParticleRendering`, `TiledGBufferRendering`, `LateDrawablePresenting`, etc.)
3. Add `RendererType` enum case
4. Register in `Engine.InitRenderer()` switch
