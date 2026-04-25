# Plan: Thread `MDLTextureSampler.transform` to Material-Sampling Shaders

## Summary

Implement static, per-texture UV transform support for the material texture slots the current shaders already sample: `baseColor`, `normal`, and `specular`. Do not mutate `MDLTexture`, `MTLTexture`, or sampler state. Instead, capture each `MDLTextureSampler.transform` during material import, store it in a new shared GPU struct, bind that struct alongside `MaterialProperties`, and apply the matching matrix to UVs immediately before each `sample()` call.

Use `matrix_float4x4` end-to-end for the UV transform payload. That keeps the ABI simple across Swift/C/Metal and matches the project’s existing shared-type pattern. In v1, sampler transforms are static only: if a `MDLTransform` is animated, freeze it to the earliest sample and log that animation is not supported yet.

## Key Changes

### Shared interfaces and GPU data

- Add a new shared struct in `TFSCommon.h`:
  - `MaterialTextureTransforms`
  - Fields:
    - `matrix_float4x4 baseColorUVTransform`
    - `matrix_float4x4 normalUVTransform`
    - `matrix_float4x4 specularUVTransform`
- Add a new buffer index in `TFSBufferIndices`:
  - `TFSBufferIndexMaterialTextureTransforms = 12`
- Add `extension MaterialTextureTransforms: sizeable` plus an identity initializer in `MetalTypes.swift`.
- Keep `MaterialProperties` unchanged. Texture mapping state should not be mixed into the shading-properties struct.

### Material import and CPU-side storage

- Extend `Material` with:
  - `public var textureTransforms = MaterialTextureTransforms()`
- In the `.texture` branch of `Material.populateMaterial(with:)`:
  - Read `property.textureSamplerValue`
  - Load `sampler.texture` exactly as today
  - Convert `sampler.transform` to a frozen `matrix_float4x4`
  - Store that matrix into the transform slot matching the semantic
- Semantic mapping for v1:
  - `.baseColor` -> `baseColorUVTransform`
  - `.tangentSpaceNormal` -> `normalUVTransform`
  - `.specular` -> `specularUVTransform`
- Leave `.string` and `.URL` loads at identity. Imported assets using `asset.loadTextures()` should already arrive as `.texture` samplers with identity transforms when no authored transform exists.
- Animated `MDLTransform` handling:
  - If `minimumTime != maximumTime` or `keyTimes.count > 1`, log once per material/property that animated sampler transforms are unsupported in v1
  - Freeze to the earliest sample by using the `matrix` property, which Model I/O documents as the earliest value when animation data exists

### Draw path and shader usage

- In both material-binding paths in `DrawManager.swift`, bind the new transform payload with `setFragmentBytes` immediately after `MaterialProperties`.
- Add a shared shader helper in the common shader include used by material-sampling fragment shaders:
  - `inline float2 ApplyUVTransform(float2 uv, float4x4 transform)`
  - Implementation:
    - `return (transform * float4(uv, 0.0, 1.0)).xy;`
- Update all fragment shaders that currently sample material textures:
  - forward material shader
  - deferred G-buffer variants
  - transparency variants
- For each sampled map, compute a UV specific to that map before sampling:
  - base color uses `baseColorUVTransform`
  - normal uses `normalUVTransform`
  - specular uses `specularUVTransform`
- Do not change:
  - `TextureLoader`
  - `MTKTextureLoader` origin handling
  - `MTLSamplerState` binding behavior
  - tessellation, skybox, particles, or shadow sampling paths

## Before / After Code Samples

### Before: sampler transform is observed but discarded

```swift
case .texture:
    let sourceTexture = property.textureSamplerValue!.texture!
    if let textureTransform = property.textureSamplerValue?.transform {
        print("ehh")
    }
    let texture = TextureLoader.Texture(mdlTexture: sourceTexture)
    populateTexture(texture, for: semantic)
```

```swift
if applyMaterials {
    applyMaterialTextures(submesh.material!, with: renderEncoder)

    var materialProps = submesh.material!.properties
    renderEncoder.setFragmentBytes(&materialProps,
                                   length: MaterialProperties.stride,
                                   index: TFSBufferIndexMaterial.index)
}
```

```metal
float2 texCoord = rd.textureCoordinate;

if (!is_null_texture(baseColorMap)) {
    color = baseColorMap.sample(sampler2d, texCoord);
}
```

### After: capture, bind, and apply per-texture UV transforms

```c
typedef struct {
    matrix_float4x4 baseColorUVTransform;
    matrix_float4x4 normalUVTransform;
    matrix_float4x4 specularUVTransform;
} MaterialTextureTransforms;
```

```swift
case .texture:
    guard let sampler = property.textureSamplerValue,
          let sourceTexture = sampler.texture else { break }

    let texture = TextureLoader.Texture(mdlTexture: sourceTexture)
    let uvTransform = Self.frozenSamplerTransformMatrix(from: sampler.transform)

    populateTexture(texture, uvTransform: uvTransform, for: semantic)
```

```swift
private static func frozenSamplerTransformMatrix(from transform: MDLTransform?) -> float4x4 {
    guard let transform else { return matrix_identity_float4x4 }

    if transform.minimumTime != transform.maximumTime || transform.keyTimes.count > 1 {
        print("[Material] Animated MDLTextureSampler.transform is not supported yet; freezing earliest sample.")
    }

    return transform.matrix
}
```

```swift
if applyMaterials {
    applyMaterialTextures(submesh.material!, with: renderEncoder)

    var materialProps = submesh.material!.properties
    renderEncoder.setFragmentBytes(&materialProps,
                                   length: MaterialProperties.stride,
                                   index: TFSBufferIndexMaterial.index)

    var textureTransforms = submesh.material!.textureTransforms
    renderEncoder.setFragmentBytes(&textureTransforms,
                                   length: MaterialTextureTransforms.stride,
                                   index: TFSBufferIndexMaterialTextureTransforms.index)
}
```

```metal
inline float2 ApplyUVTransform(float2 uv, float4x4 transform) {
    return (transform * float4(uv, 0.0, 1.0)).xy;
}

fragment GBufferData gbuffer_fragment_material(...,
                                               constant MaterialTextureTransforms &uvTransforms [[ buffer(TFSBufferIndexMaterialTextureTransforms) ]],
                                               sampler sampler2d [[ sampler(0) ]],
                                               texture2d<half> baseColorMap [[ texture(TFSTextureIndexBaseColor) ]],
                                               texture2d<half> normalMap [[ texture(TFSTextureIndexNormal) ]],
                                               texture2d<half> specularMap [[ texture(TFSTextureIndexSpecular) ]],
                                               ...)
{
    const float2 baseColorUV = ApplyUVTransform(in.tex_coord.xy, uvTransforms.baseColorUVTransform);
    const float2 normalUV = ApplyUVTransform(in.tex_coord.xy, uvTransforms.normalUVTransform);
    const float2 specularUV = ApplyUVTransform(in.tex_coord.xy, uvTransforms.specularUVTransform);

    if (!is_null_texture(baseColorMap)) {
        base_color_sample = baseColorMap.sample(sampler2d, baseColorUV);
    }

    if (!in.useObjectColor && !is_null_texture(normalMap)) {
        normal_sample = normalMap.sample(sampler2d, normalUV);
    }

    if (!in.useObjectColor && !is_null_texture(specularMap)) {
        specular_contrib = specularMap.sample(sampler2d, specularUV).r;
    }
}
```

## Test Plan

- Build macOS and iOS targets after the shared header and buffer-index change to catch ABI or shader-binding mismatches.
- Add a focused unit test for the CPU-side default:
  - new `MaterialTextureTransforms()` initializes all matrices to identity
- Add a focused unit test for material import:
  - a `MDLMaterialProperty` with a `MDLTextureSampler` transform populates the matching slot and leaves unrelated slots at identity
- Runtime verification scenario 1:
  - base-color texture with authored scale/offset renders correctly without changing mesh UVs or texture bytes
- Runtime verification scenario 2:
  - base-color and normal map with different sampler transforms use different UVs in shader
- Runtime regression scenario:
  - asset with no sampler transform renders identically to current behavior
- Runtime edge-case scenario:
  - animated sampler transform logs and uses earliest sample without crashing or corrupting bindings

## Assumptions and Defaults

- v1 supports static-only sampler transforms; animated `MDLTransform` data is intentionally frozen to the earliest sample.
- v1 covers only the texture slots already sampled by current shaders: `baseColor`, `normal`, `specular`, and transparency paths that sample base color.
- The transform is applied in the shader, not baked into the texture or mesh UVs.
- `matrix_float4x4` is used instead of `float3x3` to avoid cross-language alignment risk and to stay consistent with existing shared project types.
- `MDLTextureSampler.hardwareFilter` remains out of scope for this change; sampler filtering and wrap behavior stay as-is.
