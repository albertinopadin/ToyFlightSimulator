# Plan: Per-Texture UV Transforms from `MDLTextureSampler.transform`

**Date:** 2026-04-25
**Supersedes:** `plans/codex/mdltexturesampler_transform_shader_plan_2026-04-22.md`
**Research basis:** `investigations/claude/texture_uv_transform_research_2026-04-25.md`

## Summary

Capture each `MDLTextureSampler.transform` per texture slot during material import, store as a 2D affine `matrix_float3x3` (the spec-conformant form used by glTF `KHR_texture_transform` and USD `UsdTransform2d`), bind alongside `MaterialProperties`, and apply to UVs immediately before each `sample()` call in the fragment shader.

This works uniformly for any asset whose materials reach `Material.populateMaterial(_:)` — OBJ/MTL via `MDLAssetIO`, USD/USDZ via `MDLAsset`, or any other ModelIO-compatible importer. Material properties of type `.string` and `.URL` get identity transforms (no sampler info available, which is the correct fallback). Material properties of type `.texture` extract the transform from the sampler when present.

Static-only in v1: animated `MDLTransform` data is intentionally frozen to the earliest sample by reading `transform.matrix`, which the SDK documents as "*The matrix, at minimumTime*" (`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.4.sdk/System/Library/Frameworks/ModelIO.framework/Headers/MDLTransform.h:30-31`).

## Design Decisions

| Concern | Decision | Rationale |
|---|---|---|
| Storage type | `matrix_float3x3` (48 B in MSL/simd) | Matches glTF `KHR_texture_transform` spec, O3DE, Three.js. UVs are 2D — `mat4` wastes 28 B/slot and hides a hidden assumption that the 4×4 has no Z component. |
| 2D extraction | Pull upper-left 2×2 + translation column from `MDLTransform.matrix` | Robust regardless of which Euler axis the importer used for 2D rotation. Works for any source format. |
| Time sampling | `transform.matrix` (= value at `minimumTime`) | SDK docstring guarantees earliest sample. No `localTransformAtTime:` needed for static. |
| Slots covered | base color, normal, specular, **opacity** | Match `Material` slots that are sampled or will be sampled. Opacity included for transparency-path readiness even though no current shader samples it. |
| Texture origin | Standardize on `.bottomLeft` everywhere | Fixes the existing inconsistency in `TextureLoader.swift` (`.topLeft` in 2 paths, `.bottomLeft` in 4). UV transforms only behave consistently if origin is consistent. |
| Identity skip | `bool hasTextureTransforms` flag in transform struct | Most assets in this repo (OBJ via MTL) won't produce non-identity transforms. One uniform branch per shader skips 4 mat3-vec3 multiplies on the common path. Matches existing precedent (`MaterialProperties.isLit`). |
| Binding location | Inside `applyMaterialTextures` in `DrawManager.swift` | Transform binding is inherently coupled to texture binding; same place to update both. |

## Buffer/Header Changes

### `TFSCommon.h`

**Add a new shared struct and buffer index.** Place `MaterialTextureTransforms` after `MaterialProperties` and `TFSBufferIndexMaterialTextureTransforms = 12` after `TFSBufferIndexJointBuffer = 11`.

#### Before

```c
typedef struct {
    simd_float4 color;
    simd_float3 ambient;
    simd_float3 diffuse;
    simd_float3 specular;

    float shininess;
    float opacity;

    bool isLit;
} MaterialProperties;

// ...

typedef enum {
    TFSBufferIndexMeshVertex        = 0,
    // ...
    TFSBufferIndexMaterial          = 9,
    TFSBufferIndexTerrain           = 10,
    TFSBufferIndexJointBuffer       = 11
} TFSBufferIndices;
```

#### After

```c
typedef struct {
    simd_float4 color;
    simd_float3 ambient;
    simd_float3 diffuse;
    simd_float3 specular;

    float shininess;
    float opacity;

    bool isLit;
} MaterialProperties;

// 2D affine UV transforms per texture slot. Layout matches glTF KHR_texture_transform
// (mat3, applied as (M * float3(uv, 1)).xy). Default-constructed values are identity.
typedef struct {
    matrix_float3x3 baseColorUVTransform;
    matrix_float3x3 normalUVTransform;
    matrix_float3x3 specularUVTransform;
    matrix_float3x3 opacityUVTransform;
    bool hasTextureTransforms;  // true → at least one slot has a non-identity transform
} MaterialTextureTransforms;

// ...

typedef enum {
    TFSBufferIndexMeshVertex                  = 0,
    // ...
    TFSBufferIndexMaterial                    = 9,
    TFSBufferIndexTerrain                     = 10,
    TFSBufferIndexJointBuffer                 = 11,
    TFSBufferIndexMaterialTextureTransforms   = 12
} TFSBufferIndices;
```

## Swift Changes

### `MetalTypes.swift` — Sizeable conformance + identity init

#### After

```swift
extension MaterialTextureTransforms: sizeable { }

extension MaterialTextureTransforms {
    init() {
        self.init(
            baseColorUVTransform: matrix_identity_float3x3,
            normalUVTransform:    matrix_identity_float3x3,
            specularUVTransform:  matrix_identity_float3x3,
            opacityUVTransform:   matrix_identity_float3x3,
            hasTextureTransforms: false
        )
    }
}
```

(If `matrix_identity_float3x3` isn't already defined locally, add `let matrix_identity_float3x3 = matrix_float3x3(diagonal: simd_float3(1, 1, 1))` to a math helper.)

### `Material.swift` — Capture transforms during import

This is the central correctness change. Three things happen here:

1. Replace the `print("ehh")` placeholder with real transform extraction.
2. Add `textureTransforms` storage.
3. Set `hasTextureTransforms` whenever any slot got a non-identity matrix.

#### Before (`Material.swift:10-78`, abbreviated)

```swift
struct Material: sizeable {
    public var name: String = "material"
    public var properties = MaterialProperties()

    public var baseColorTexture: MTLTexture?
    public var normalMapTexture: MTLTexture?
    public var specularTexture: MTLTexture?
    public var roughnessTexture: MTLTexture?
    public var metallicTexture: MTLTexture?
    public var ambientOcclusionTexture: MTLTexture?
    public var opacityTexture: MTLTexture?

    // ...

    private mutating func populateMaterial(with material: MDLMaterial) {
        for semantic in MDLMaterialSemantic.allCases {
            for property in material.properties(with: semantic) {
                switch property.type {
                    case .string:
                        if let stringValue = property.stringValue {
                            let texture = TextureLoader.Texture(name: stringValue)
                            populateTexture(texture, for: semantic)
                        }

                    case .URL:
                        if let textureURL = property.urlValue {
                            let texture = TextureLoader.Texture(url: textureURL)
                            populateTexture(texture, for: semantic)
                        }

                    case .texture:
                        let sourceTexture = property.textureSamplerValue!.texture!
                        if let textureTransform = property.textureSamplerValue?.transform {
                            print("ehh")
                        }
                        let texture = TextureLoader.Texture(mdlTexture: sourceTexture)
                        populateTexture(texture, for: semantic)

                    // ...
                }
            }
        }
    }
}
```

#### After

```swift
struct Material: sizeable {
    public var name: String = "material"
    public var properties = MaterialProperties()
    public var textureTransforms = MaterialTextureTransforms()

    public var baseColorTexture: MTLTexture?
    public var normalMapTexture: MTLTexture?
    public var specularTexture: MTLTexture?
    public var roughnessTexture: MTLTexture?
    public var metallicTexture: MTLTexture?
    public var ambientOcclusionTexture: MTLTexture?
    public var opacityTexture: MTLTexture?

    // ...

    private mutating func populateMaterial(with material: MDLMaterial) {
        for semantic in MDLMaterialSemantic.allCases {
            for property in material.properties(with: semantic) {
                switch property.type {
                    case .string:
                        if let stringValue = property.stringValue {
                            let texture = TextureLoader.Texture(name: stringValue)
                            populateTexture(texture, for: semantic)
                        }
                        // .string carries no sampler — transform stays identity.

                    case .URL:
                        if let textureURL = property.urlValue {
                            let texture = TextureLoader.Texture(url: textureURL)
                            populateTexture(texture, for: semantic)
                        }
                        // .URL carries no sampler — transform stays identity.

                    case .texture:
                        guard let sampler = property.textureSamplerValue,
                              let sourceTexture = sampler.texture else { break }

                        let texture = TextureLoader.Texture(mdlTexture: sourceTexture)
                        populateTexture(texture, for: semantic)

                        let uvAffine = Self.uvAffine(from: sampler.transform, materialName: name)
                        populateTextureTransform(uvAffine, for: semantic)

                    // ... unchanged ...
                }
            }
        }
    }

    private mutating func populateTextureTransform(_ uvAffine: matrix_float3x3,
                                                   for semantic: MDLMaterialSemantic) {
        guard !Self.isIdentity(uvAffine) else { return }

        switch semantic {
            case .baseColor:           textureTransforms.baseColorUVTransform = uvAffine
            case .tangentSpaceNormal:  textureTransforms.normalUVTransform    = uvAffine
            case .specular:            textureTransforms.specularUVTransform  = uvAffine
            case .opacity:             textureTransforms.opacityUVTransform   = uvAffine
            default:                   return  // semantic not yet wired to a transform slot
        }
        textureTransforms.hasTextureTransforms = true
    }

    /// Extracts a 2D affine UV transform from an `MDLTransform`. Returns identity if `transform` is nil.
    ///
    /// We pull the 2D effect directly from the resolved 4×4 (upper-left 2×2 + translation column),
    /// rather than from `translation.xy`/`rotation.z`/`scale.xy` separately. This is robust regardless of
    /// which Euler axis the importer used to encode 2D rotation.
    ///
    /// `MDLTransform.matrix` is documented as "The matrix, at minimumTime", so for animated transforms
    /// this freezes to the earliest sample. v1 logs a one-shot warning when animation data is present.
    private static func uvAffine(from transform: MDLTransform?, materialName: String) -> matrix_float3x3 {
        guard let transform else { return matrix_identity_float3x3 }

        if transform.minimumTime != transform.maximumTime || transform.keyTimes.count > 1 {
            print("[Material:\(materialName)] Animated MDLTextureSampler.transform is not supported yet; freezing to earliest sample.")
        }

        let m = transform.matrix
        return matrix_float3x3(
            simd_float3(m.columns.0.x, m.columns.0.y, 0),  // scaled/rotated U basis
            simd_float3(m.columns.1.x, m.columns.1.y, 0),  // scaled/rotated V basis
            simd_float3(m.columns.3.x, m.columns.3.y, 1)   // translation
        )
    }

    private static func isIdentity(_ m: matrix_float3x3) -> Bool {
        let eps: Float = 1e-6
        return abs(m.columns.0.x - 1) < eps && abs(m.columns.0.y) < eps &&
               abs(m.columns.1.x)     < eps && abs(m.columns.1.y - 1) < eps &&
               abs(m.columns.2.x)     < eps && abs(m.columns.2.y)     < eps
    }
}
```

### `TextureLoader.swift` — Standardize on `.bottomLeft`

Two paths still default to `.topLeft` and need to be flipped. The codex investigation flagged this as a correctness problem — UV transforms inherit it, so it must be fixed in this same change.

#### Before (`TextureLoader.swift`)

```swift
init(textureName: String, textureExtension: String = "png", origin: MTKTextureLoader.Origin = .topLeft) {
    self._textureName = textureName
    self._textureExtension = textureExtension
    self._origin = origin
}

// ...

public static func LoadTexture(name: String,
                               scale: CGFloat = 1.0,
                               origin: MTKTextureLoader.Origin = .bottomLeft) -> MTLTexture? {
```

Wait — `LoadTexture` already defaults to `.bottomLeft`. The actually-inconsistent path is the instance `init` (which feeds `loadTextureFromBundle`).

#### After

```swift
init(textureName: String, textureExtension: String = "png", origin: MTKTextureLoader.Origin = .bottomLeft) {
    self._textureName = textureName
    self._textureExtension = textureExtension
    self._origin = origin
}
```

(Run a grep for `\.topLeft` in the `AssetPipeline` directory and flip any remaining instances unless they have a documented reason for being top-left.)

### `DrawManager.swift` — Bind transforms next to textures

Bundle the binding into `applyMaterialTextures` so the textures and their transforms always travel together.

#### Before (`DrawManager.swift:469-489`)

```swift
private static func applyMaterialTextures(_ material: Material, with renderEncoder: MTLRenderCommandEncoder) {
    renderEncoder.setFragmentSamplerState(Graphics.SamplerStates[.Linear], index: 0)

    if let baseColorTexture = material.baseColorTexture {
        renderEncoder.setFragmentTexture(baseColorTexture, index: TFSTextureIndexBaseColor.index)
    } else {
        renderEncoder.setFragmentTexture(nil, index: TFSTextureIndexBaseColor.index)
    }

    if let normalMapTexture = material.normalMapTexture {
        renderEncoder.setFragmentTexture(normalMapTexture, index: TFSTextureIndexNormal.index)
    } else {
        renderEncoder.setFragmentTexture(nil, index: TFSTextureIndexNormal.index)
    }

    if let specularTexture = material.specularTexture {
        renderEncoder.setFragmentTexture(specularTexture, index: TFSTextureIndexSpecular.index)
    } else {
        renderEncoder.setFragmentTexture(nil, index: TFSTextureIndexSpecular.index)
    }
}
```

#### After

```swift
private static func applyMaterialTextures(_ material: Material, with renderEncoder: MTLRenderCommandEncoder) {
    renderEncoder.setFragmentSamplerState(Graphics.SamplerStates[.Linear], index: 0)

    if let baseColorTexture = material.baseColorTexture {
        renderEncoder.setFragmentTexture(baseColorTexture, index: TFSTextureIndexBaseColor.index)
    } else {
        renderEncoder.setFragmentTexture(nil, index: TFSTextureIndexBaseColor.index)
    }

    if let normalMapTexture = material.normalMapTexture {
        renderEncoder.setFragmentTexture(normalMapTexture, index: TFSTextureIndexNormal.index)
    } else {
        renderEncoder.setFragmentTexture(nil, index: TFSTextureIndexNormal.index)
    }

    if let specularTexture = material.specularTexture {
        renderEncoder.setFragmentTexture(specularTexture, index: TFSTextureIndexSpecular.index)
    } else {
        renderEncoder.setFragmentTexture(nil, index: TFSTextureIndexSpecular.index)
    }

    var textureTransforms = material.textureTransforms
    renderEncoder.setFragmentBytes(&textureTransforms,
                                   length: MaterialTextureTransforms.stride,
                                   index: TFSBufferIndexMaterialTextureTransforms.index)
}
```

The two `Draw(...)` paths (lines ~405 and ~448) already call `applyMaterialTextures` and then bind `MaterialProperties`. They don't need additional changes — the transform is bundled into `applyMaterialTextures`.

## Shader Changes

A shared helper goes in a header that all material-sampling fragment shaders import. The repo currently has no `MaterialUtils.h`-style helper file, so add it inline in `TFSCommon.h` (Metal-side only via `__METAL_VERSION__` guard) or in `ShaderDefinitions.h`. Prefer `ShaderDefinitions.h` since it already has a `__METAL_VERSION__` block for GBuffer raster-order-group output struct.

### Shared helper (place in `ShaderDefinitions.h` under `#ifdef __METAL_VERSION__`)

```metal
// Apply a 2D affine UV transform. Identity-skip is checked by caller via hasTextureTransforms.
inline float2 ApplyUVTransform(float2 uv, float3x3 transform) {
    return (transform * float3(uv, 1.0)).xy;
}
```

### Per-shader changes

The shaders to update (everything that samples a material texture):

| Shader file | Fragment function | Slots sampled |
|---|---|---|
| `GBuffer.metal` | `gbuffer_fragment_material` | base, normal, specular |
| `TiledDeferredGBuffer.metal` | `tiled_deferred_gbuffer_fragment` | base, normal |
| `TiledMSAAGBuffer.metal` | `tiled_msaa_gbuffer_fragment` | base, normal |
| `OrderIndependentTransparency.metal` | `transparent_material_fragment` | base (normal commented out) |
| `SinglePassDeferredTransparency.metal` | `single_pass_deferred_transparency_fragment` | base |
| `TiledDeferredTransparency.metal` | `tiled_deferred_transparency_fragment` | base |
| `TiledMSAATransparency.metal` | `tiled_msaa_transparency_fragment` | base (MSAA averaged) |

Each fragment function adds one parameter binding and replaces raw `in.tex_coord.xy` (or `in.uv`) with transformed UVs. The `hasTextureTransforms` flag gates the multiply on the common (identity) path.

#### Before (`GBuffer.metal:111-141`)

```metal
fragment GBufferData gbuffer_fragment_material(ColorInOut                   in           [[ stage_in ]],
                                               constant MaterialProperties &material     [[ buffer(TFSBufferIndexMaterial) ]],
                                               sampler                      sampler2d    [[ sampler(0) ]],
                                               texture2d<half>              baseColorMap [[ texture(TFSTextureIndexBaseColor) ]],
                                               texture2d<half>              normalMap    [[ texture(TFSTextureIndexNormal) ]],
                                               texture2d<half>              specularMap  [[ texture(TFSTextureIndexSpecular) ]],
                                               depth2d<float>               shadowMap    [[ texture(TFSTextureIndexShadow) ]])
{
    half4 base_color_sample;
    half4 normal_sample;
    half specular_contrib;

    if (in.useObjectColor) {
        base_color_sample = half4(in.objectColor);
    } else if (!is_null_texture(baseColorMap)) {
        base_color_sample = baseColorMap.sample(sampler2d, in.tex_coord.xy);
    } else {
        base_color_sample = half4(in.color);
    }

    if (!in.useObjectColor && !is_null_texture(normalMap)) {
        normal_sample = normalMap.sample(sampler2d, in.tex_coord.xy);
    } else {
        normal_sample = half4(in.normal, 1.0);
    }

    if (!in.useObjectColor && !is_null_texture(specularMap)) {
        specular_contrib = specularMap.sample(sampler2d, in.tex_coord.xy).r;
    } else {
        specular_contrib = 1.0;
    }
    // ...
}
```

#### After

```metal
fragment GBufferData gbuffer_fragment_material(ColorInOut                       in              [[ stage_in ]],
                                               constant MaterialProperties     &material        [[ buffer(TFSBufferIndexMaterial) ]],
                                               constant MaterialTextureTransforms &uvXforms     [[ buffer(TFSBufferIndexMaterialTextureTransforms) ]],
                                               sampler                          sampler2d       [[ sampler(0) ]],
                                               texture2d<half>                  baseColorMap    [[ texture(TFSTextureIndexBaseColor) ]],
                                               texture2d<half>                  normalMap       [[ texture(TFSTextureIndexNormal) ]],
                                               texture2d<half>                  specularMap     [[ texture(TFSTextureIndexSpecular) ]],
                                               depth2d<float>                   shadowMap       [[ texture(TFSTextureIndexShadow) ]])
{
    float2 baseUV     = in.tex_coord.xy;
    float2 normalUV   = in.tex_coord.xy;
    float2 specularUV = in.tex_coord.xy;
    if (uvXforms.hasTextureTransforms) {
        baseUV     = ApplyUVTransform(in.tex_coord.xy, uvXforms.baseColorUVTransform);
        normalUV   = ApplyUVTransform(in.tex_coord.xy, uvXforms.normalUVTransform);
        specularUV = ApplyUVTransform(in.tex_coord.xy, uvXforms.specularUVTransform);
    }

    half4 base_color_sample;
    half4 normal_sample;
    half specular_contrib;

    if (in.useObjectColor) {
        base_color_sample = half4(in.objectColor);
    } else if (!is_null_texture(baseColorMap)) {
        base_color_sample = baseColorMap.sample(sampler2d, baseUV);
    } else {
        base_color_sample = half4(in.color);
    }

    if (!in.useObjectColor && !is_null_texture(normalMap)) {
        normal_sample = normalMap.sample(sampler2d, normalUV);
    } else {
        normal_sample = half4(in.normal, 1.0);
    }

    if (!in.useObjectColor && !is_null_texture(specularMap)) {
        specular_contrib = specularMap.sample(sampler2d, specularUV).r;
    } else {
        specular_contrib = 1.0;
    }
    // ...
}
```

#### Before (`TiledDeferredGBuffer.metal:90-112`, abbreviated)

```metal
fragment GBufferOut
tiled_deferred_gbuffer_fragment(VertexOut                   in                  [[ stage_in ]],
                                sampler                     sampler2d           [[ sampler(0) ]],
                                texture2d<half>             baseColorTexture    [[ texture(TFSTextureIndexBaseColor) ]],
                                texture2d<half>             normalTexture       [[ texture(TFSTextureIndexNormal) ]],
                                depth2d<float>              shadowTexture       [[ texture(TFSTextureIndexShadow) ]]) {
    // ...
    color = float4(baseColorTexture.sample(sampler2d, in.uv));
    // ...
    normal = float4(normalTexture.sample(sampler2d, in.uv));
}
```

#### After

```metal
fragment GBufferOut
tiled_deferred_gbuffer_fragment(VertexOut                          in              [[ stage_in ]],
                                constant MaterialTextureTransforms &uvXforms       [[ buffer(TFSBufferIndexMaterialTextureTransforms) ]],
                                sampler                            sampler2d       [[ sampler(0) ]],
                                texture2d<half>                    baseColorTexture[[ texture(TFSTextureIndexBaseColor) ]],
                                texture2d<half>                    normalTexture   [[ texture(TFSTextureIndexNormal) ]],
                                depth2d<float>                     shadowTexture   [[ texture(TFSTextureIndexShadow) ]]) {
    float2 baseUV   = in.uv;
    float2 normalUV = in.uv;
    if (uvXforms.hasTextureTransforms) {
        baseUV   = ApplyUVTransform(in.uv, uvXforms.baseColorUVTransform);
        normalUV = ApplyUVTransform(in.uv, uvXforms.normalUVTransform);
    }
    // ...
    color = float4(baseColorTexture.sample(sampler2d, baseUV));
    // ...
    normal = float4(normalTexture.sample(sampler2d, normalUV));
}
```

The other shaders follow the same pattern. For the four transparency shaders that only sample base color, only `baseColorUVTransform` is consumed — the unused mat3s are sent over the bus but never read (they're cheap).

When transparency starts sampling `opacityTexture`, the `opacityUVTransform` slot is already wired and no further plumbing is needed.

## File-by-File Punch List

1. **`ToyFlightSimulator Shared/Graphics/Shaders/TFSCommon.h`** — add `MaterialTextureTransforms` struct; add `TFSBufferIndexMaterialTextureTransforms = 12` to enum.
2. **`ToyFlightSimulator Shared/Graphics/Shaders/ShaderDefinitions.h`** — add `ApplyUVTransform` helper inside `#ifdef __METAL_VERSION__`.
3. **`ToyFlightSimulator Shared/AssetPipeline/Material.swift`** — add `textureTransforms` field; replace `print("ehh")` placeholder; add `populateTextureTransform`, `uvAffine(from:materialName:)`, `isIdentity` helpers.
4. **`ToyFlightSimulator Shared/AssetPipeline/Libraries/Textures/TextureLoader.swift`** — change `init(textureName:textureExtension:origin:)` default origin to `.bottomLeft`. Audit other `.topLeft` literals in `AssetPipeline/`.
5. **`ToyFlightSimulator Shared/Math/MetalTypes.swift`** (or wherever `sizeable` extensions live) — add `MaterialTextureTransforms: sizeable` and identity initializer.
6. **`ToyFlightSimulator Shared/Managers/DrawManager.swift`** — extend `applyMaterialTextures` to bind transforms.
7. **Seven shader files** — add `MaterialTextureTransforms` parameter; add identity-skip block; replace raw UV reads with transformed UVs.

## Test Plan

- [ ] **Unit:** `MaterialTextureTransforms()` initializer produces all-identity matrices and `hasTextureTransforms == false`.
- [ ] **Unit:** `Material.uvAffine(from:materialName:)` with `nil` returns `matrix_identity_float3x3`.
- [ ] **Unit:** `Material.uvAffine(from:materialName:)` with a transform whose 4×4 has translation (0.5, 0.25), scale (2, 3), rotation 0 produces mat3 `[2,0,0; 0,3,0; 0.5,0.25,1]` (column-major).
- [ ] **Unit:** `Material.uvAffine(from:materialName:)` with a transform whose 4×4 has rotation only around Z=π/2 produces mat3 with column 0 ≈ `(0,1,0)` and column 1 ≈ `(-1,0,0)`.
- [ ] **Unit:** `Material.isIdentity(matrix_identity_float3x3) == true`; perturb one element and it returns `false`.
- [ ] **Unit:** Importing a `MDLMaterial` with `.string` and `.URL` properties leaves `textureTransforms` at identity and `hasTextureTransforms == false`.
- [ ] **Unit:** Importing a `MDLMaterial` with a `.texture` property whose sampler has a non-identity transform populates the matching slot and sets `hasTextureTransforms == true`.
- [ ] **Unit:** Different transforms across `baseColor`, `normal`, `specular`, `opacity` slots produce four different mat3s.
- [ ] **Build:** macOS Debug + iOS Simulator Debug build clean (catches ABI mismatch between C struct and shader struct).
- [ ] **Runtime:** Existing OBJ/MTL assets (F16/F18/F35/Temple) render identically to current behavior.
- [ ] **Runtime:** A USDZ asset with a `UsdTransform2d` on its base color renders with the transform applied (visible scale/offset).
- [ ] **Runtime:** A USDZ asset with different `UsdTransform2d` per slot renders correctly per slot (e.g., base color tiled 2× while normal tiled 1×).
- [ ] **Runtime:** Animated `UsdTransform2d` logs the warning once per material/property and freezes to the earliest sample without crashing.
- [ ] **Runtime smoke:** All six renderers (`SinglePassDeferredLighting`, `TiledDeferred`, `TiledDeferredMSAA`, `TiledMSAATessellated`, `OrderIndependentTransparency`, `ForwardPlusTileShading` if buildable) start a scene without GPU validation errors.
- [ ] **GPU capture:** Confirm `MaterialTextureTransforms` buffer is bound to fragment buffer index 12 in a captured frame.

## Out of Scope

- Animated UV transforms (frozen to earliest sample with a log warning).
- `MDLTextureSampler.hardwareFilter` → `MTLSamplerState` mapping (sampler filter/wrap behavior unchanged).
- Roughness, metallic, ambient-occlusion, emission UV transforms — currently no shader samples those textures.
- KTX/block-compressed origin handling (separate concern; flagged in the texture-origin investigation).
- Triplanar mapping or detail-map UV transforms (not present in the renderer).
- Per-UV-channel transforms (`texCoord` override in glTF) — repo only uses one UV channel.
