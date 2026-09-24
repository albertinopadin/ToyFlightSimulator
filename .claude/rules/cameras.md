---
paths:
  - "ToyFlightSimulator Shared/GameObjects/Cameras/**"
  - "ToyFlightSimulator Shared/Managers/CameraManager.swift"
  - "ToyFlightSimulator Shared/Scenes/**"
  - "ToyFlightSimulatorTests/Cameras/**"
---
# Camera system

Moved verbatim from the root `CLAUDE.md` on 2026-09-23 so it loads only when working on the files matched by `paths` above. Keep it current the same way as `CLAUDE.md`.

### Camera System (GameObjects/Cameras/)
`Camera` base (FOV, near/far, projection matrix from `Transform.perspectiveProjection`). `viewMatrix` is a lazy, generation-checked getter: it reads `modelMatrix` (bringing the world cache current), recomputes only when `worldMatrixGeneration` changed, and derives via the `computeViewMatrix(from:)` override point — base/`DebugCamera` use the plain inverse, so at most one inverse per camera per frame, and parent-following needs no per-frame hook. `DebugCamera` (WASD + mouselook). `AttachedCamera` (parents to node, follows aircraft; signature default offset `[0, 2, -4]` since +Z is forward, but scenes pass the aircraft's `cameraOffset` — a per-subclass override on `Aircraft`, default `[0, 10, -20]`) supports re-attachment for aircraft swaps: `attach(to:)` first detaches from any current parent and zeroes accumulated rotation. It overrides `computeViewMatrix` to strip parent scale via `scaleStrippedInverse()` — normalizes basis columns, keeps translation — so a camera on a scaled aircraft gets a rigid view matrix and view-space distances stay in true world units, which CSM cascade fitting depends on. `CameraManager.CurrentCamera` is now optional (`Camera?`) — guarded everywhere instead of force-unwrapped, so scene transitions and pre-scene-set states no longer crash. `CameraManager.Update()` skips parented cameras (they're updated through scene-graph traversal — prevents double `doUpdate`). 'C' key (`DiscreteCommand.CycleCamera`, debounced on the update thread in `GameScene.doUpdate`) cycles registered cameras in registration order; CameraManager's registry is an ordered identity-deduped array (registration order = cycle order = slot indices for `SetCamera(at:)` direct selection), scenes opt in by registering extra cameras via `addCamera(_, false)` (FlightboxWithPhysics adds a DebugCamera), and inactive cameras skip input via `isActiveCamera`.
