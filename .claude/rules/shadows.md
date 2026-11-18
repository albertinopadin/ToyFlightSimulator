---
paths:
  - "ToyFlightSimulator Shared/Shadows/**"
  - "ToyFlightSimulator Shared/Display/Protocols/ShadowRendering.swift"
  - "ToyFlightSimulator Shared/Graphics/Shaders/Shadow.metal"
  - "ToyFlightSimulator Shared/Graphics/Shaders/Lighting.metal"
  - "ToyFlightSimulatorTests/Shadows/**"
---
# Shadows

Moved verbatim from the root `CLAUDE.md` on 2026-09-23 so it loads only when working on the files matched by `paths` above. Keep it current the same way as `CLAUDE.md`.

### Shadows (Shadows/, Display/Protocols/ShadowRendering.swift, Shadow.metal, Lighting.metal)
4-cascade cascaded shadow maps. `ShadowCascadeFitting` splits the view frustum with the uniform/logarithmic hybrid (λ = 0.5), fits each slice with a rotation-invariant bounding sphere (radius depends only on FOV/aspect/slice depth, not camera rotation) and snaps the light-space origin to world-space texel multiples — together these kill shimmer as the camera moves. Straight-overhead sun is handled by building the light basis directly with an X-axis up-vector fallback instead of `Transform.look` (the old NaN-matrix bug). `ShadowCamera` wraps per-cascade view-projection + depth range; ortho Z padding is additive to bound casters when the depth range straddles 0.

Snap phase and the floating origin: along each of the light's X and Y axes (`ShadowCascadeFitting.lightBasis`, used by both the fit and the phase update), the texel grid of cascade i is the set of positions `phase_i + k * texelSize_i` for whole k. `fitCascades` takes the phases as `cascadeSnapPhases` (`[double2]`, meters; the default, empty, means zero, a grid through the current origin) and returns the texel sizes it used in `CascadeFit.texelSizes`. Each directional `LightObject` stores both (`_cascadeSnapPhases`, `_cascadeTexelSizes`). `SceneManager.updateFloatingOrigin` calls `shiftShadowSnapPhases(by:)` with the offset it subtracts from the nodes, which sets `phase = positiveRemainder(phase - dot(lightAxis, offset), texelSize)` (`snapPhasesAfterOriginShift`). Without it the grid stays tied to the origin while the world moves by an offset that is not a whole number of texels, and every static shadow edge jumps by up to half a texel on the shift. The phases are Double so a chain of shifts adds no Float rounding, and they are positions in the current frame, so they stay smaller than one texel however far the flight goes. `fitCascades` also accepts a phase outside `0 ..< texelSize`. The pure functions are covered by `ShadowCascadeFittingTests` (one shift, 200 shifts in a row, each with a control that leaves the phase update out); the two call sites (`LightObject`, `SceneManager`) need Metal and have no automated test.

Shadow map storage: one `depth32Float` `texture2DArray`, 4096² × 4 slices. `ShadowRendering` encodes one render pass per cascade, binding that cascade's VP at buffer index 13 (`TFSBufferIndexShadowCascadeVP`); no `setDepthBias` — bias is slope-scaled in-shader from `shadowWorldSlack`. Light space is forward-Z ortho (clear 1.0, `.less*`) even though the main camera is reverse-Z. Sampling (Lighting.metal): `SelectCascade` by view-space depth → 5×5 hardware `sample_compare` PCF → cross-fade to the next cascade over the last 10% of each cascade's range (`CASCADE_BLEND_FRACTION = 0.1`); out-of-bounds projection falls through to the next cascade (texel-snap edge case).
