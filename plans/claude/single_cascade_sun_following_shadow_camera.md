# Single-Cascade Sun-Following Shadow Camera

## Context

The "Sun Line" bug ([investigation](../../debugging/claude/sun_line_shadow_frustum_cutoff.md), [followup](../../debugging/claude/sun_line_shadow_frustum_cutoff_followup.md)) is caused by the directional-light shadow map being pinned to a fixed ±100 orthographic box around the world origin (`LightObject.swift:15`) with its view aimed at `.zero` (`LightObject.swift:18`). As the camera flies away, the visible scene leaves the shadow frustum, and a hard `× 0.5` brightness step appears along the world line where the shadow camera's coverage ends.

The architectural confusion behind it: `LightObject` treats one entity (the sun) as both a light direction AND a shadow camera. A true directional light has only direction; a shadow camera (which exists to render a finite-resolution shadow map) is a separate concept that should follow the visible region. The followup doc concluded the canonical single-cascade fix is **sun-follow**: each frame, move the shadow camera to wherever the main camera is, oriented along the (fixed) light direction.

This plan implements that fix end-to-end with the smallest surface area that keeps the architecture honest:

1. Introduce a `ShadowCamera` value type as the per-frame "synthesis camera" — view + ortho proj sized to a configurable shadow radius, lifted along the light direction from a focus point.
2. Add a `direction` concept to `LightData` (world-space unit vector pointing from surface toward sun); refactor `Lighting::CalculateDirectionalLighting` to consume it instead of `normalize(light.position)`.
3. Make `Lighting::CalculateShadow` and `Lighting::CalculateShadowMSAA` return `1.0` (fully lit) when shadow texture coords fall outside `[0,1]`, so any future shadow-frustum miss reads as "no shadow" rather than as a `clamp_to_edge` self-shadow.
4. Refactor `LightObject.update()` so for `Directional` lights it builds the `ShadowCamera` against `CameraManager.CurrentCamera` each frame, and exposes per-light tunables (`shadowRadius`, `shadowLift`).
5. Keep `LightObject.setPosition` working for backward compatibility: existing scenes that call `sun.setPosition(0, 200, 4)` continue to imply "direction = normalize((0,200,4))" unless `setLightDirection` is called explicitly. The sun's visual mesh (red sphere) keeps using `position`.

This is a focused fix. The followup doc's larger recommended cleanups — splitting `LightObject` into `DirectionalLight`/`PointLight` subclasses, deleting the dead `Omni` enum case, reverse-Z shadow refactor — are out of scope here and tracked at the end.

## Outcome

After this lands:

- The bright/dim boundary on the ground disappears in `FlightboxWithPhysics` because the shadow camera follows the F-22.
- The shadow camera covers a `2 * shadowRadius` square around the current camera each frame (default `shadowRadius = 500`, `shadowLift = 2000`).
- The shader's directional-lighting math reads a real `direction` field — moving the sun in scene code stops mysteriously dimming the lighting (the `// TODO: Why does position with z = 0 result in much darker lighting` comment in `FlightboxWithPhysics.swift:86` becomes obsolete and is removed).
- Any future shadow-frustum miss (camera flying far above the shadow lift, looking down past the radius) renders as "fully lit," not as "shadowed by clamped texel."
- Existing scenes keep working with no behavioral regression: they all just set `sun.setPosition(...)` today, and that still implies the same world-space sun direction.
- Shadow map resolution per world-space unit on the ground: with `R = 500` and an 8192² shadow texture, each shadow texel maps to ~0.12 world units — sharp F-22 shadows out to a 500-unit radius around the camera.

## Critical Files

- `ToyFlightSimulator Shared/GameObjects/LightObject.swift` — most of the refactor
- `ToyFlightSimulator Shared/Graphics/Shaders/Lighting.metal` — directional-lighting and shadow-sampling shader changes
- `ToyFlightSimulator Shared/Graphics/Shaders/TFSCommon.h` — `LightData` schema (`direction` field)
- `ToyFlightSimulator Shared/Managers/LightManager.swift` — minor: `lightEyeDirection` population uses the new direction
- **NEW** `ToyFlightSimulator Shared/GameObjects/ShadowCamera.swift` — new value type
- `ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift` — remove obsolete TODO comment
- (No changes required) the seven scene files that call `sun.setPosition(...)` — backward-compat shim covers them
- (No changes required) `Shadow.metal`, `TiledDeferredGBuffer.metal`, `TiledMSAAGBuffer.metal`, `GBuffer.metal`, `TiledDeferredDirectionalLight.metal`, `DirectionalLight.metal` — they consume `LightData.shadowViewProjectionMatrix` and the (refactored) `Lighting::Calculate*` helpers, both of which keep their signatures stable enough that the call sites don't need to change

## Reused Existing Infrastructure

- `CameraManager.CurrentCamera` ([`Managers/CameraManager.swift:10`](../../ToyFlightSimulator%20Shared/Managers/CameraManager.swift#L10)) — already optional, already tracks the active camera.
- `Transform.orthographicProjection` ([`Math/Transform.swift:59-71`](../../ToyFlightSimulator%20Shared/Math/Transform.swift#L59)) — left-handed ortho, forward-Z. Reused as-is per the followup doc's Q3 conclusion.
- `Transform.look(eye:target:up:)` ([`Math/Transform.swift:104-117`](../../ToyFlightSimulator%20Shared/Math/Transform.swift#L104)).
- `Y_AXIS` ([`Math/Math.swift:14`](../../ToyFlightSimulator%20Shared/Math/Math.swift#L14)).
- The existing depth-bias settings ([`Display/Protocols/ShadowRendering.swift:73`](../../ToyFlightSimulator%20Shared/Display/Protocols/ShadowRendering.swift#L73)) — unchanged; bias values are independent of frustum size.

---

## 1. New `ShadowCamera` value type

**New file:** `ToyFlightSimulator Shared/GameObjects/ShadowCamera.swift`

Self-contained value type. No dependencies on `LightObject` so it can be reused later for CSM (an array of these per directional light) or for spot-light shadows (perspective variant — left as future work).

```swift
//
//  ShadowCamera.swift
//  ToyFlightSimulator
//

import simd

/// Per-frame "synthesis camera" used to render a directional light's shadow map.
/// Decoupled from the LightObject's own pose: the LightObject defines a direction
/// (pointing from surfaces toward the sun); the ShadowCamera is positioned to
/// keep the visible region inside a finite orthographic frustum.
///
/// Sun-follow construction: each frame, compute against the main camera so the
/// shadow coverage tracks the player. See `LightObject.update()`.
struct ShadowCamera {
    /// Unit vector from the focus point toward the sun. The shadow camera is
    /// positioned `lift` units along this direction from `focus`.
    let direction: float3

    /// World-space point the shadow camera looks at. Typically the main camera's
    /// position (or the camera position projected onto the ground plane).
    let focus: float3

    /// Half-extent of the orthographic box (covers `2 * radius` per side).
    /// Larger values cover more ground at the cost of shadow texel density.
    let radius: Float

    /// Distance from `focus` along `direction` to place the shadow eye. Must be
    /// large enough that all shadow casters between the camera and the sun fit
    /// between the camera's `near` and `far`.
    let lift: Float

    var eye: float3 { focus + direction * lift }

    var viewMatrix: float4x4 {
        // `up = Y_AXIS` matches all other camera/light conventions in the codebase.
        // Degenerate when `direction` is exactly parallel to Y_AXIS; callers should
        // avoid pointing the sun straight up. With a flight-sim "sun roughly
        // overhead but tilted" placement this is never an issue in practice.
        Transform.look(eye: eye, target: focus, up: Y_AXIS)
    }

    var projectionMatrix: float4x4 {
        // Forward-Z ortho (see TiledDeferredDepthStencils.swift:10-13 comment for
        // why the shadow path is intentionally not reverse-Z).
        Transform.orthographicProjection(-radius, radius, -radius, radius, 1, 2 * lift)
    }

    var viewProjectionMatrix: float4x4 { projectionMatrix * viewMatrix }
}
```

---

## 2. `LightData` gets a real `direction` field

**File:** `ToyFlightSimulator Shared/Graphics/Shaders/TFSCommon.h`

### Before

```c
typedef struct {
    LightType type;
    matrix_float4x4 modelMatrix;
    matrix_float4x4 viewProjectionMatrix;
    matrix_float4x4 shadowViewProjectionMatrix;
    matrix_float4x4 shadowTransformMatrix;
    simd_float3 lightEyeDirection;
    
    simd_float3 position;
    simd_float3 color;
    float brightness;
    float radius;  // TODO: This only applies to point lights; perhaps should have Directional/PointLightData
    simd_float3 attenuation;
    
    float ambientIntensity;
    float diffuseIntensity;
    float specularIntensity;
} LightData;
```

### After

```c
typedef struct {
    LightType type;
    matrix_float4x4 modelMatrix;
    matrix_float4x4 viewProjectionMatrix;
    matrix_float4x4 shadowViewProjectionMatrix;
    matrix_float4x4 shadowTransformMatrix;

    // World-space unit vector pointing FROM lit surfaces TO the light source.
    // For Directional lights this is the canonical light direction used by the
    // lighting shader (`dot(normal, direction)`). Populated by LightObject.update().
    // For Point lights this is unused; the shader recomputes per-fragment from
    // `light.position - worldPosition`.
    simd_float3 direction;

    // Eye-space transform of `direction`, recomputed each frame from the active
    // view matrix. Still populated for any specular paths that want it in eye
    // space, but no longer the primary input for diffuse lighting.
    simd_float3 lightEyeDirection;

    simd_float3 position;
    simd_float3 color;
    float brightness;
    float radius;  // TODO: This only applies to point lights; perhaps should have Directional/PointLightData
    simd_float3 attenuation;

    float ambientIntensity;
    float diffuseIntensity;
    float specularIntensity;
} LightData;
```

Notes:
- Adds `simd_float3 direction;` ahead of `lightEyeDirection`. Keeps `lightEyeDirection` for now; `LightManager` already populates it from the view matrix and a few legacy specular paths reference it.
- `simd_float3` aligns to 16 bytes — net `LightData` size grows by 16 bytes. All consumers use `LightData.stride`, so no manual offset arithmetic to update.
- `position` stays. It's still meaningful for the visualization mesh on the `Sun` GameObject, and for `LightManager.GetDirectionalLightData(viewMatrix:)` to compute `lightEyeDirection`.

---

## 3. Refactor `Lighting::CalculateDirectionalLighting` to take a direction

**File:** `ToyFlightSimulator Shared/Graphics/Shaders/Lighting.metal`

### Before (lines 62-71)

```glsl
static float3 CalculateDirectionalLighting(LightData light, float3 normal, MaterialProperties material) {
    float4 baseColor = material.color;
    float3 metallic = material.shininess;
    float3 ambientOcclusion = material.ambient;
    
    float3 lightDirection = normalize(light.position);
    float nDotL = saturate(dot(normal, lightDirection));
    float3 diffuse = float3(baseColor) * (1.0 - metallic);
    return diffuse * nDotL * ambientOcclusion * light.color;
}
```

### After

```glsl
static float3 CalculateDirectionalLighting(LightData light, float3 normal, MaterialProperties material) {
    float4 baseColor = material.color;
    float3 metallic = material.shininess;
    float3 ambientOcclusion = material.ambient;

    // `light.direction` is a world-space unit vector from surfaces toward the
    // light source, populated by LightObject.update(). No per-fragment normalize
    // needed; no dependence on the (now decoupled) shadow camera position.
    float nDotL = saturate(dot(normal, light.direction));
    float3 diffuse = float3(baseColor) * (1.0 - metallic);
    return diffuse * nDotL * ambientOcclusion * light.color;
}
```

Two practical effects of removing `normalize(light.position)`:
1. The mysterious "set z = 0 and lighting goes dark" bug in `FlightboxWithPhysics.swift:86` disappears, because `light.direction` is no longer position-derived at the per-fragment level.
2. One fewer per-pixel `normalize` in the directional-light pass. Minor but measurable on full-screen quads.

`CalculatePointLighting` and `GetPhongIntensity` are NOT changed in this plan — they continue to use `light.position`, which is what a point light actually is.

---

## 4. Sampler-edge safety in `CalculateShadow` and `CalculateShadowMSAA`

**File:** `ToyFlightSimulator Shared/Graphics/Shaders/Lighting.metal`

The `address::clamp_to_edge` sampler currently returns the boundary depth value when shadow coords step outside `[0,1]`, which causes ground past the shadow frustum to self-shadow (the original SunLine mechanism). With sun-follow this scenario shrinks but doesn't vanish — a camera flying high above the shadow lift, or looking far past the radius, can still produce out-of-range coords. Make it explicit: outside the frustum means "no shadow info available, render fully lit."

### Before (lines 73-85, `CalculateShadow`)

```glsl
static float CalculateShadow(float4 shadowPosition, depth2d<float> shadowTexture) {
    // shadow calculation
    float3 position = shadowPosition.xyz / shadowPosition.w;
    float2 xy = position.xy;
    xy = xy * 0.5 + 0.5;
    xy.y = 1 - xy.y;
    constexpr sampler s(coord::normalized,
                        filter::nearest,
                        address::clamp_to_edge,
                        compare_func:: less);
    float shadow_sample = shadowTexture.sample(s, xy);
    return (position.z > shadow_sample + 0.001) ? 0.5 : 1;
}
```

### After

```glsl
static float CalculateShadow(float4 shadowPosition, depth2d<float> shadowTexture) {
    float3 position = shadowPosition.xyz / shadowPosition.w;
    float2 xy = position.xy;
    xy = xy * 0.5 + 0.5;
    xy.y = 1 - xy.y;

    // Outside the shadow frustum we have no occluder info. Treat as fully lit
    // rather than letting clamp_to_edge return the boundary texel's depth
    // (which produces ground self-shadow past the frustum edge). Also guard
    // the forward-Z near/far range: position.z outside [0, 1] means the
    // fragment is in front of the shadow near plane or behind the far plane.
    if (any(xy < 0.0) || any(xy > 1.0) || position.z < 0.0 || position.z > 1.0) {
        return 1.0;
    }

    constexpr sampler s(coord::normalized,
                        filter::nearest,
                        address::clamp_to_edge,
                        compare_func:: less);
    float shadow_sample = shadowTexture.sample(s, xy);
    return (position.z > shadow_sample + 0.001) ? 0.5 : 1;
}
```

### Before (lines 87-105, `CalculateShadowMSAA`)

```glsl
static float CalculateShadowMSAA(float4 shadowPosition, depth2d_ms<float> shadowTexture) {
    float3 position = shadowPosition.xyz / shadowPosition.w;
    float2 xy = position.xy;
    xy = xy * 0.5 + 0.5;
    xy.y = 1 - xy.y;
    
    float shadow = 0;
    
    uint2 coords = uint2(uint(xy.x * shadowTexture.get_width()), uint(xy.y * shadowTexture.get_height()));
    uint numSamples = shadowTexture.get_num_samples();
    
    for (uint i = 0; i < numSamples; ++i) {
        shadow += shadowTexture.read(coords, i);
    }
    
    shadow /= numSamples;
    
    return (position.z > shadow + 0.001) ? 0.5 : 1;
}
```

### After

```glsl
static float CalculateShadowMSAA(float4 shadowPosition, depth2d_ms<float> shadowTexture) {
    float3 position = shadowPosition.xyz / shadowPosition.w;
    float2 xy = position.xy;
    xy = xy * 0.5 + 0.5;
    xy.y = 1 - xy.y;

    // See CalculateShadow for rationale: out-of-frustum reads as fully lit.
    if (any(xy < 0.0) || any(xy > 1.0) || position.z < 0.0 || position.z > 1.0) {
        return 1.0;
    }

    uint2 coords = uint2(uint(xy.x * shadowTexture.get_width()),
                         uint(xy.y * shadowTexture.get_height()));
    uint numSamples = shadowTexture.get_num_samples();

    float shadow = 0;
    for (uint i = 0; i < numSamples; ++i) {
        shadow += shadowTexture.read(coords, i);
    }
    shadow /= numSamples;

    return (position.z > shadow + 0.001) ? 0.5 : 1;
}
```

The legacy `GBuffer.metal` path uses `sample_compare` directly with `address::clamp_to_edge` samplers (lines 38-47 and 96/161). It has the same theoretical issue but is only used by `SinglePassDeferredLighting`, which currently sets `sun.setLightAmbientIntensity` values that hide the problem (and the SunLine bug doesn't reproduce on that renderer per the screenshot). Out of scope for this plan; add a TODO comment in `GBuffer.metal` to fix later.

---

## 5. `LightObject` refactor

**File:** `ToyFlightSimulator Shared/GameObjects/LightObject.swift`

### Before

```swift
import MetalKit

class LightObject: GameObject {
    var lightType: LightType
    var lightData = LightData()
    // TODO: What should the light projection matrix be ???
//    let projectionMatrix: float4x4 = Transform.orthographicProjection(-100, 100, -100, 100, -100, 100)
    let projectionMatrix: float4x4 = Transform.orthographicProjection(-100, 100, -100, 100, 0.01, 1000)
    var viewMatrix: float4x4 {
//        Transform.look(eye: self.modelMatrix.columns.3.xyz, target: .zero, up: Y_AXIS)
        Transform.look(eye: self.getPosition(), target: .zero, up: Y_AXIS)
    }
    
    // When calculating texture coordinates to sample from shadow map, flip the y/t coordinate and
    // convert from the [-1, 1] range of clip coordinates to [0, 1] range of
    // used for texture sampling
    let shadowScale = Transform.scaleMatrix(.init(0.5, -0.5, 1))
    let shadowTranslate = Transform.translationMatrix(.init(0.5, 0.5, 0))
    
    private var _modelType: ModelType = .None
    
    // TODO: What RPS is appropriate for a LightObject ???
    init(name: String, lightType: LightType = Directional) {
        self.lightType = lightType
        super.init(name: name, modelType: .None)
        self.lightData.shadowTransformMatrix = shadowTranslate * shadowScale
    }
    
    // TODO: What RPS is appropriate for a LightObject ???
    init(name: String, lightType: LightType = Directional, modelType: ModelType = .Sphere) {
        self.lightType = lightType
        self._modelType = modelType
        super.init(name: name, modelType: modelType)
        self.lightData.shadowTransformMatrix = shadowTranslate * shadowScale
    }
    
    override func update() {
        super.update()
        self.lightData.type = self.lightType
        self.lightData.modelMatrix = self.modelMatrix
        self.lightData.viewProjectionMatrix = projectionMatrix * viewMatrix
//        let position = self.modelMatrix.columns.3.xyz
//        self.lightData.position = position
//        self.lightData.eyeDirection = normalize(float4(-position, 1))
        
        self.lightData.position = self.getPosition()
//        self.lightData.eyeDirection = normalize(float4(-self.getPosition(), 1))
//        let shadowViewMatrix = Transform.look(eye: position, target: .zero, up: Y_AXIS)
//        let shadowViewMatrix = Transform.look(eye: position, target: self.lightData.eyeDirection.xyz * 10.0, up: Y_AXIS)
        let shadowViewMatrix = Transform.look(eye: self.getPosition(), target: .zero, up: Y_AXIS)
        self.lightData.shadowViewProjectionMatrix = projectionMatrix * shadowViewMatrix
    }
}
```

### After

```swift
import MetalKit

class LightObject: GameObject {
    var lightType: LightType
    var lightData = LightData()

    // Configuration for the per-frame shadow camera (Directional lights only).
    // Defaults chosen for FlightboxWithPhysics-scale scenes (1M ground, F-22 at
    // flight speeds). Override per-scene via setShadowRadius/setShadowLift.
    private var _shadowRadius: Float = 500
    private var _shadowLift:   Float = 2000

    // Explicit world-space direction (from surfaces TOWARD the sun). If nil,
    // direction is derived from `getPosition()` for backward compatibility with
    // scenes that only call `setPosition` to aim the sun.
    private var _explicitDirection: float3?

    // Shadow-coord transform from clip-space [-1,1] to UV [0,1] with Y flip.
    // Kept as a constant since legacy GBuffer.metal still consumes
    // `LightData.shadowTransformMatrix`. Tiled deferred path derives the
    // transform inline in CalculateShadow.
    private let shadowScale     = Transform.scaleMatrix(.init(0.5, -0.5, 1))
    private let shadowTranslate = Transform.translationMatrix(.init(0.5, 0.5, 0))

    private var _modelType: ModelType = .None

    init(name: String, lightType: LightType = Directional) {
        self.lightType = lightType
        super.init(name: name, modelType: .None)
        self.lightData.shadowTransformMatrix = shadowTranslate * shadowScale
    }

    init(name: String, lightType: LightType = Directional, modelType: ModelType = .Sphere) {
        self.lightType = lightType
        self._modelType = modelType
        super.init(name: name, modelType: modelType)
        self.lightData.shadowTransformMatrix = shadowTranslate * shadowScale
    }

    /// Override the world-space direction the light shines from. Pass a vector
    /// pointing FROM lit surfaces TO the sun (gets normalized internally).
    /// If never called, direction is inferred from `getPosition()`.
    func setLightDirection(_ dir: float3) {
        _explicitDirection = normalize(dir)
    }

    /// Half-extent of the orthographic shadow frustum, in world units. Smaller
    /// values give sharper shadows but a smaller covered area around the camera.
    func setShadowRadius(_ radius: Float) { _shadowRadius = radius }

    /// Distance to lift the shadow eye along the light direction. Must be
    /// larger than the tallest shadow caster's height above the focus point.
    func setShadowLift(_ lift: Float) { _shadowLift = lift }

    /// World-space unit vector from surfaces toward the sun.
    /// Explicit setter wins; otherwise derived from position (legacy behavior).
    var direction: float3 {
        if let d = _explicitDirection { return d }
        let p = self.getPosition()
        let lengthSq = simd_length_squared(p)
        return lengthSq > .ulpOfOne ? p / sqrt(lengthSq) : Y_AXIS
    }

    override func update() {
        super.update()
        self.lightData.type        = self.lightType
        self.lightData.modelMatrix = self.modelMatrix
        self.lightData.position    = self.getPosition()
        self.lightData.direction   = self.direction

        if self.lightType == Directional {
            updateShadowCamera()
        }
    }

    /// Build a per-frame ShadowCamera focused on the active main camera and
    /// stash its matrices in `lightData`. No-ops if no camera is active yet
    /// (matrices keep their last-good values, which is fine for the first
    /// frame before SceneManager.SetScene completes camera registration).
    private func updateShadowCamera() {
        guard let cam = CameraManager.CurrentCamera else { return }
        let shadowCamera = ShadowCamera(direction: self.direction,
                                        focus: cam.getPosition(),
                                        radius: _shadowRadius,
                                        lift: _shadowLift)
        let svp = shadowCamera.viewProjectionMatrix
        lightData.shadowViewProjectionMatrix = svp
        lightData.viewProjectionMatrix       = svp
    }
}

extension LightObject {
    public func setLightColor(_ color: float3) {
        self.lightData.color = color
        if _modelType != .None {
            self.setColor(float4(color, 1.0))
        }
    }
    public func setLightColor(_ r: Float, _ g: Float, _ b: Float) { setLightColor([r, g, b]) }
    public func getLightColor() -> SIMD3<Float> { return self.lightData.color }

    public func setLightBrightness(_ brightness: Float) { self.lightData.brightness = brightness }
    public func getLightBrightness() -> Float { return self.lightData.brightness }

    public func setLightAmbientIntensity(_ intensity: Float) { self.lightData.ambientIntensity = intensity }
    public func getLightAmbientIntensity() -> Float { return self.lightData.ambientIntensity }

    public func setLightDiffuseIntensity(_ intensity: Float) { self.lightData.diffuseIntensity = intensity }
    public func getLightDiffuseIntensity() -> Float { return self.lightData.diffuseIntensity }

    public func setLightSpecularIntensity(_ intensity: Float) { self.lightData.specularIntensity = intensity }
    public func getLightSpecularIntensity() -> Float { return self.lightData.specularIntensity }

    public func setLightRadius(_ radius: Float) { self.lightData.radius = radius }
    public func getLightRadius() -> Float { return self.lightData.radius }
}
```

Key changes:
- `projectionMatrix` (constant) deleted; replaced by per-frame `ShadowCamera` construction in `updateShadowCamera()`.
- `viewMatrix` (computed prop pinning `target: .zero`) deleted.
- New `direction` computed property: explicit override or `normalize(position)` fallback for backward compat.
- New tunables: `setLightDirection`, `setShadowRadius`, `setShadowLift`.
- `update()` writes `direction` into `LightData` and rebuilds the shadow camera matrices each frame against the active camera.
- All the commented-out `eyeDirection` / `position` lines from the old `update()` are gone. The `LightManager.GetDirectionalLightData(viewMatrix:)` path still populates `lightEyeDirection` from `position`, so legacy specular shaders that consume it keep working.

---

## 6. `LightManager` — populate eye-space direction from the new field

**File:** `ToyFlightSimulator Shared/Managers/LightManager.swift`

`LightManager.GetDirectionalLightData(viewMatrix:)` and `SetDirectionalLightData(...)` both write `lightEyeDirection` by computing `normalize(viewMatrix * float4(light.getPosition(), 1)).xyz`. That was correct under the old "position = direction proxy" semantics. Now that we have a real `direction` field, populate `lightEyeDirection` as the eye-space transform of `direction` instead — preserving its semantics (unit vector in eye space pointing toward the light) without depending on position being "where the sun is."

### Before (lines 54-62)

```swift
public static func GetDirectionalLightData(viewMatrix: float4x4) -> [LightData] {
    withLock(lightLock) {
        for light in Self._directionalLights {
            light.lightData.lightEyeDirection =
                normalize(viewMatrix * float4(light.getPosition(), 1)).xyz
        }
        return Self._directionalLights.map { $0.lightData }
    }
}
```

### After

```swift
public static func GetDirectionalLightData(viewMatrix: float4x4) -> [LightData] {
    withLock(lightLock) {
        for light in Self._directionalLights {
            // Transform the world-space light direction into eye space.
            // `direction` is already populated by LightObject.update().
            let worldDir = float4(light.lightData.direction, 0)
            light.lightData.lightEyeDirection = normalize((viewMatrix * worldDir).xyz)
        }
        return Self._directionalLights.map { $0.lightData }
    }
}
```

### Before (lines 70-95, inside `SetDirectionalLightData`)

```swift
let count: Int = withLock(lightLock) {
    Self._directionalDataScratch.removeAll(keepingCapacity: true)
    for light in Self._directionalLights {
        light.lightData.lightEyeDirection =
            normalize(viewMatrix * float4(light.getPosition(), 1)).xyz
        Self._directionalDataScratch.append(light.lightData)
    }
    return Self._directionalDataScratch.count
}
```

### After

```swift
let count: Int = withLock(lightLock) {
    Self._directionalDataScratch.removeAll(keepingCapacity: true)
    for light in Self._directionalLights {
        let worldDir = float4(light.lightData.direction, 0)
        light.lightData.lightEyeDirection = normalize((viewMatrix * worldDir).xyz)
        Self._directionalDataScratch.append(light.lightData)
    }
    return Self._directionalDataScratch.count
}
```

The `cameraPosition` parameter to `SetDirectionalLightData` is no longer read after this change but stays in the signature for ABI compatibility (no caller-site updates needed). Future cleanup can remove it.

---

## 7. Scene cleanup

**File:** `ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift`

The "why does z = 0 make lighting dark" puzzle goes away because the directional-lighting shader now consumes `direction` (which gets normalized away from a magnitude-zero position via the `Y_AXIS` fallback in `LightObject.direction`) instead of `normalize(position)` directly.

### Before (lines 86-87)

```swift
        // TODO: Why does position with z = 0 result in much darker lighting ???
        sun.setPosition(0, jetPos.y + 100, 4)
```

### After

```swift
        sun.setPosition(0, jetPos.y + 100, 4)
```

All other scene call sites (`FlightboxScene`, `SandboxScene`, `BallPhysicsScene`, `PhysicsStressTestScene`, `FreeCamFlightboxScene`, `FlightboxWithTerrain`) continue to work without changes — `setPosition(...)` keeps implying the same direction via the `_explicitDirection ?? normalize(position)` fallback.

Scenes that want sharper shadows over a smaller area, or vice versa, can opt in:

```swift
// Optional, per-scene:
sun.setShadowRadius(250)   // tighter coverage, sharper shadows
sun.setShadowLift(1000)
sun.setLightDirection(normalize(float3(1, 5, 2)))  // explicit, ignores position
```

---

## 8. Verification plan

Functional checks (run on `FlightboxWithPhysics`, the screenshotted scene):

1. **The line is gone.** Start the scene, rotate the camera 180°. The bright/dim boundary in the original screenshot should not appear. Fly the F-22 forward for several seconds — no boundary should sweep into view from any direction.
2. **Shadow coverage tracks the camera.** Use Xcode's GPU frame capture to inspect the shadow map texture. It should show the F-22, the F-16, and nearby debris each frame — not a fixed view of objects-near-origin.
3. **Shadow sharpness sanity.** Land or hover the F-22, look at its shadow on the ground from `DebugCamera` (press C). The shadow edges should be reasonably crisp (~0.12 world units per texel at `R=500`).
4. **`z = 0` no longer darkens.** Temporarily change `sun.setPosition(0, jetPos.y + 100, 4)` to `sun.setPosition(0, jetPos.y + 100, 0)` and confirm lighting brightness is unchanged (it was previously dramatically darker).
5. **All other scenes still render.** Switch via menu through `Flightbox`, `Sandbox`, `BallPhysics`, `PhysicsStressTest`, `FreeCamFlightbox`, `FlightboxWithTerrain`. No new visual regressions; lighting matches the previous baseline for each.
6. **All renderer modes.** In the renderer menu, switch between `SinglePassDeferredLighting`, `TiledDeferred`, `TiledDeferredMSAA`, `TiledMSAATessellated`, `OrderIndependentTransparency`. The directional-light direction change touches `Lighting.metal` which is imported by both tiled and SinglePass paths — confirm both look right.
7. **Frustum-edge safety.** Climb to altitude > `shadowLift` (2000 units) and look straight down. With the sampler-edge fix, the world far below the camera should still appear fully lit, not blanket-shadowed.

Build/test gates:

- `xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGNING_ALLOWED=NO` must succeed.
- `xcodebuild test -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGNING_ALLOWED=NO` — existing tests pass. No new tests added in this plan; `ShadowCamera` is data, not logic worth a unit test, and the behavioral verification is visual.

---

## 9. Risks and rollback

| Risk | Mitigation |
|---|---|
| Adding `simd_float3 direction` to `LightData` shifts the offsets of every field after it. | All Metal-side consumers use the shared `TFSCommon.h` typedef; Swift-side consumers use `LightData.stride`. No manual offset arithmetic anywhere. Recompile the project once and offsets re-align everywhere. |
| First-frame race: `LightObject.update()` runs before `CameraManager.CurrentCamera` is set. | `updateShadowCamera()` early-returns if no current camera; the matrices keep their last-good (or zero-init) values for that single frame. No artifact visible because the renderer also requires a current camera to draw. |
| Per-light scenes assume specific direction from position. | Backward-compat shim: `direction` falls back to `normalize(position)` if `setLightDirection` is never called. All existing scenes already set `position`, and the implied direction is identical to today's. |
| Sun positioned at the world origin makes `normalize(position)` undefined. | `direction` getter guards `lengthSq > .ulpOfOne` and falls back to `Y_AXIS`. No scene currently puts the sun at the origin; the guard is belt-and-braces. |
| `ShadowCamera.viewMatrix` becomes degenerate if `direction == ±Y_AXIS` (look() up vector parallel to forward). | Documented in the doc comment. No current scene does this. Future: if a scene wants sun straight overhead, use `direction = normalize(float3(.001, 1, 0))` or extend `ShadowCamera` to pick a non-degenerate `up`. |
| Larger shadow extent (R=500 vs R=100 today) reduces texels-per-world-unit by 5×. | Original shadow was effectively useless for the visible scene because the camera was usually outside the frustum. Net visual quality improves dramatically even at 5× lower texel density. |

Rollback: revert all touched files in a single commit. The change set is contained to `LightObject.swift`, `Lighting.metal`, `TFSCommon.h`, `LightManager.swift`, the new `ShadowCamera.swift`, and the one-line cleanup in `FlightboxWithPhysics.swift`.

---

## 10. Extending to Cascaded Shadow Maps (future work)

Single-cascade sun-follow is the right starting point but has known shortcomings:
- One uniform texel density (`shadowRadius`-scaled) across the entire covered region. Shadows under the F-22 are at the same resolution as shadows at the radius edge.
- Hard cutoff at `radius`. Anything past it gets the sampler-edge fallback (fully lit), so distant objects cast no shadow at all.
- Shadow texels "swim" as the camera moves — not snapped to texel-aligned grid.

Cascaded Shadow Maps (CSM) addresses all three by splitting the view frustum into depth ranges and rendering a separate shadow map per range, each with its own tightly-fitted ortho box.

### Architectural extension

`ShadowCamera` becomes the per-cascade unit; a directional light owns N of them:

```swift
struct DirectionalShadowCascades {
    let cascades: [ShadowCamera]            // ordered near→far, e.g. 4 entries
    let splitDistances: [Float]             // view-space depths separating cascades
}
```

`LightData` extends to:

```c
typedef struct {
    // ... existing fields ...
    matrix_float4x4 cascadeShadowViewProjectionMatrices[MAX_CASCADES];  // e.g. 4
    float          cascadeSplitDistances[MAX_CASCADES];
    uint           cascadeCount;
} LightData;
```

`shadowViewProjectionMatrix` (singular) stays as a back-compat alias of `cascadeShadowViewProjectionMatrices[0]` if you want to land cascades without touching every shader at once.

### Cascade fitting

Per frame, for each cascade `i ∈ [0, N)`:
1. Compute the world-space corners of the slice of the main camera's view frustum between `splitDistances[i-1]` (or main camera near) and `splitDistances[i]`.
2. Transform those 8 corners into the light's view space using `Transform.look(eye: focus, target: focus + direction, up: Y_AXIS)` with `focus = center_of_those_8_corners`.
3. Compute the axis-aligned bounding box of the corners in light view space → that's the tight ortho box for this cascade.
4. Snap the box origin to the nearest shadow-texel boundary (eliminates texel swimming).
5. Build a `ShadowCamera` from those parameters.

Split distance strategy: use the standard practical hybrid of uniform and logarithmic splits (e.g., `cascade_i = lerp(uniform_i, log_i, 0.5)` per Microsoft's CSM whitepaper). With 4 cascades and main-camera `(near, far) = (0.01, 1_000_000)`, typical splits land around `[2, 25, 250, 5000]` world units, with everything past 5000 receiving no shadow (acceptable for a flight sim).

### Shadow generation

`encodeShadowMapPass` becomes a loop:

```swift
for (i, cascade) in cascades.enumerated() {
    let descriptor = makeCascadeShadowRenderPassDescriptor(
        shadowMap: shadowMapArray,
        sliceIndex: i
    )
    encodeRenderPass(into: commandBuffer, using: descriptor, label: "Shadow Map Pass [\(i)]") { encoder in
        // Bind cascade.viewProjectionMatrix instead of LightData.shadowViewProjectionMatrix
        ...
        DrawManager.DrawShadows(with: encoder)
    }
}
```

The shadow map texture changes from a single 8192² `depth32Float` to a `texture2d_array` of N slices (each likely smaller, e.g. 2048² × 4 slices). Total memory is comparable to today's single 8K map but resolution is concentrated where it matters.

### Shader changes

`CalculateShadow` picks the cascade based on the fragment's view-space depth:

```glsl
static float CalculateShadow(LightData light, float3 worldPosition, float viewDepth,
                             depth2d_array<float> shadowTextureArray) {
    // Pick cascade based on view-space depth
    uint cascadeIdx = light.cascadeCount - 1;
    for (uint i = 0; i < light.cascadeCount - 1; i++) {
        if (viewDepth < light.cascadeSplitDistances[i]) {
            cascadeIdx = i;
            break;
        }
    }

    float4 shadowPos = light.cascadeShadowViewProjectionMatrices[cascadeIdx] *
                       float4(worldPosition, 1);
    float3 position = shadowPos.xyz / shadowPos.w;
    float2 xy = position.xy * 0.5 + 0.5;
    xy.y = 1 - xy.y;

    if (any(xy < 0.0) || any(xy > 1.0) || position.z < 0.0 || position.z > 1.0) {
        return 1.0;  // off-cascade: fully lit (no further cascade available)
    }

    constexpr sampler s(coord::normalized, filter::nearest,
                        address::clamp_to_edge, compare_func::less);
    float sample = shadowTextureArray.sample(s, xy, cascadeIdx);
    return (position.z > sample + 0.001) ? 0.5 : 1;
}
```

GBuffer fragment shaders pass world position (already in `VertexOut.worldPosition`) and view-space depth (recomputable from `gl_FragCoord.z` plus camera matrices, or fetched from a depth GBuffer attachment).

Optional polish: cascade blending — when a fragment is within ε of a split boundary, sample both cascades and lerp. Eliminates the visible seam where cascade i ends and cascade i+1 begins.

### Estimated effort

| Phase | Surface area |
|---|---|
| Single-cascade sun-follow (this plan) | ~150 LOC across 5 files |
| Add cascade array to `LightData` + back-compat alias | ~30 LOC, no shader behavior change |
| Cascade fitting (`DirectionalShadowCascades.update(against: Camera)`) | ~100 LOC in a new `ShadowCascadeFitting.swift` |
| Texture array shadow map + per-slice render passes | ~80 LOC in `ShadowRendering.swift` + 1 new helper |
| Shader cascade selection + sampling | ~30 LOC in `Lighting.metal`; identical change to MSAA helper |
| Texel snapping (no shadow swimming) | ~10 LOC in the fitting code |
| Cascade-boundary blending (optional) | ~20 LOC in shader |

CSM is a substantial follow-on but the `ShadowCamera` value type introduced by this plan slots in as the per-cascade primitive, so the foundation is right from day one.

### Other future cleanups deferred from this plan

Per the followup doc's "Recommended minimum to land the fix" + other recommendations, these stay out of scope here:

- **Subclass `LightObject` into `DirectionalLight` / `PointLight`** — meaningful refactor across every scene file. Worth doing once spot lights or point shadows enter the picture.
- **Delete the dead `Omni` enum case** — trivial but spans `TFSCommon.h` + `LightManager` switch statements. Bundle with the subclass split.
- **Reverse-Z shadow refactor** — Q3 of the followup doc concluded "not worth it" for the orthographic case. Revisit when adding spot lights.
- **Add real ambient term in `TiledDeferredDirectionalLight.metal`** — independent shader hardening; the SinglePass renderer's `minimum_sun_diffuse_intensity = 0.4h` floor (`DirectionalLight.metal:47`) shows the pattern. Bundle with a broader PBR-ish material pass refactor.
- **Fix the `clamp_to_edge` issue in legacy `GBuffer.metal`** (`sample_compare` paths at lines 96 and 161) — same fix as `Lighting::CalculateShadow`, only affects SinglePassDeferred path. Add a TODO comment in this plan's diff.

---

## Implementation order

Recommended one-PR sequence (each step independently buildable and visually inspectable):

1. **Add `ShadowCamera.swift`** (no callers; pure additive).
2. **Extend `LightData` with `direction`** in `TFSCommon.h`. Recompile to verify offsets re-align; lighting still uses `normalize(light.position)` and behaves identically.
3. **Populate `direction` in `LightObject.update()`** but leave the shader path on `normalize(light.position)`. Visual: no change.
4. **Refactor `Lighting::CalculateDirectionalLighting` to read `light.direction`**. Visual: no change (direction == normalize(position) for all current scenes).
5. **Update `LightManager.GetDirectionalLightData` / `SetDirectionalLightData`** to derive `lightEyeDirection` from `direction`. Visual: no change.
6. **Replace `LightObject` shadow camera with `ShadowCamera`**. Visual: **SunLine goes away.** This is the load-bearing step.
7. **Add sampler-edge safety to `CalculateShadow` + `CalculateShadowMSAA`**. Visual: regions past the shadow frustum render fully lit instead of `× 0.5`.
8. **Remove the obsolete TODO comment in `FlightboxWithPhysics.swift`**.

Each step is bisectable; if a regression appears, it landed in exactly one of these eight commits.
