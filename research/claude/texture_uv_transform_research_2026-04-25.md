# Per-Texture UV Transforms in Real-Time Renderers

**Date:** 2026-04-25
**Scope:** Whether it is industry-standard practice to capture a per-texture UV transform during material import and apply it to texture coordinates in a shader before sampling — and how this is done in glTF, USD, Godot, O3DE, Unity, Unreal, Filament, and Bevy. This research is the evidence base for evaluating the plan at `plans/codex/mdltexturesampler_transform_shader_plan_2026-04-22.md`.

## Executive Answer

Yes, it is industry-standard practice. Both major asset-interchange formats explicitly model per-texture UV transforms:

- **glTF** has `KHR_texture_transform`, defined per `textureInfo` (i.e. per texture slot — base color, normal, metallic-roughness, etc., independently).
- **USD/USDZ** has `UsdTransform2d`, inserted between `UsdPrimvarReader_float2` and `UsdUVTexture` in a Shade graph, also per `UsdUVTexture`.

ModelIO's `MDLTextureSampler.transform` exists primarily to surface the USD value into Swift — Apple's ModelIO does not import glTF natively, so the Swift surface is mainly USD-driven, but the abstraction is the same.

However, real-world engine support splits into two camps:

1. **Spec-conformant (per-texture-slot)**: Three.js, Babylon.js, PlayCanvas, UnityGLTF, the glTF reference viewer, USD Hydra. Each texture slot can have its own independent transform. Unity's authored-content default (`<TexName>_ST` convention) is also per-texture.
2. **Pragmatic (per-material)**: Godot, Bevy, Filament (historically), O3DE. They store one transform per material and apply it to every sampled texture. When a glTF is imported with different transforms per slot, they typically take the base-color transform and warn or silently ignore the others.

For a Metal renderer importing USDZ via ModelIO, the strict-correct approach is per-texture-slot. The shortcut breaks any USDZ that uses different `UsdTransform2d` per slot.

## 1. glTF `KHR_texture_transform` — The Canonical Standard

### What the Spec Says

The Khronos extension is at <https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_texture_transform>. It adds four properties to any `textureInfo` structure:

| Field | Type | Default | Meaning |
|---|---|---|---|
| `offset` | array[2] | `[0, 0]` | UV translation (UV-space units) |
| `rotation` | number | `0` | Counter-clockwise rotation, **radians** |
| `scale` | array[2] | `[1, 1]` | Per-axis UV scale |
| `texCoord` | integer | — | Optional per-slot override of the parent's UV channel index |

The spec literally provides the GLSL:

```glsl
mat3 translation = mat3(1,0,0, 0,1,0, Offset.x, Offset.y, 1);
mat3 rotation    = mat3(cos(R), sin(R), 0, -sin(R), cos(R), 0, 0,0,1);
mat3 scale       = mat3(Scale.x, 0, 0, 0, Scale.y, 0, 0, 0, 1);
mat3 matrix      = translation * rotation * scale;
vec2 uvTransformed = (matrix * vec3(uv, 1)).xy;
```

Three observations that matter for the plan:

1. **The matrix is `mat3`**, not `mat4`. UVs are 2D, the homogeneous form needs 3×3.
2. **Order is scale → rotate → translate** (right-to-left as written). Diverges from the typical 3D TRS convention.
3. **The extension is on `textureInfo`**, which is the per-slot reference. The example JSON in the spec shows it applied selectively to just the `emissiveTexture`. Per-slot is the design intent.

### Why It Exists

The spec's stated motivation, quoted: "*Chief among them is the ability to minimize the number of textures the GPU must load.*" The original use case is texture atlasing — pack several sub-textures into one image, give each material a different UV window. It's also widely used for tiling patterns (a material may want a brick texture tiled 4× while its associated normal map tiles 1×, hence per-slot transforms).

### Adoption

The spec lists these as known implementations: UnityGLTF, Babylon.js, PlayCanvas, Three.js, Blender, Gestaltor. It is one of the most widely-adopted Khronos extensions — almost universally supported in glTF viewers.

Babylon.js implements it per-texture in [`KHR_texture_transform.ts`](https://github.com/BabylonJS/Babylon.js/blob/c0e3f1480802513ac58fae99ab8307ae14120bd2/loaders/src/glTF/2.0/Extensions/KHR_texture_transform.ts), populating `uOffset`, `vOffset`, `uScale`, `vScale`, `uAng` per Babylon `Texture` instance.

## 2. USD `UsdTransform2d` and `MDLTextureSampler.transform`

### USD's Mechanism

USD's `UsdPreviewSurface` shading model documents a transform node `UsdTransform2d` (<https://openusd.org/dev/spec_usdpreviewsurface.html>) inserted between a `UsdPrimvarReader_float2` and a `UsdUVTexture`. Inputs:

- `translation` — `vec2`
- `rotation` — counter-clockwise **degrees** (note: USD uses degrees, glTF uses radians)
- `scale` — `vec2`
- Formula: `result = in * scale * rotate + translation`

This is positioned per `UsdUVTexture`, which is the per-texture-slot node in USD. So USD's model is also per-slot, just like glTF.

### What ModelIO Surfaces

Apple's `MDLTextureSampler` has a `transform: MDLTransform?` property documented as "*The transformation to be applied to texture coordinate data before sampling from the texture*" (<https://developer.apple.com/documentation/modelio/mdltexturesampler/transform>). The type is the general 3D `MDLTransform`, even though only 2D is meaningful for UVs. ModelIO does not natively import glTF, so this property is primarily populated from USDZ assets that use `UsdTransform2d`.

### Apple's Own Code Doesn't Use It

The Metal-by-Example tutorial on ModelIO materials (<https://metalbyexample.com/modelio-materials/>) explicitly punts:

> "It also contains other properties indicating the preferred transform and filtering modes for the texture. These could, respectively, be turned into a texture matrix and a sampler state to affect how Metal samples the textures, but for our simple use case, we'll ignore these properties."

The accompanying `Renderer.swift` ignores `transform` entirely. This means USDZ assets with non-identity `UsdTransform2d` render incorrectly in Apple's published samples — a documented gap.

## 3. Engine-by-Engine Survey

### Godot — Single Per-Material Transform (Vertex Shader)

Godot's `BaseMaterial3D`/`StandardMaterial3D` exposes `uv1_offset`/`uv1_scale` (UV channel 0) and `uv2_offset`/`uv2_scale` (UV channel 1) — `vec3` uniforms (third component used for triplanar Z). The generated shader in [`scene/resources/material.cpp`](https://github.com/godotengine/godot/blob/master/scene/resources/material.cpp) does the multiply in the **vertex** shader:

```glsl
UV  = UV  * uv1_scale.xy + uv1_offset.xy;
UV2 = UV2 * uv2_scale.xy + uv2_offset.xy;
```

The transformed UV is reused by every fragment-shader sample. There is no per-texture-slot transform: albedo, normal, metallic, roughness all share the UV-channel transform.

Godot historically had no UV rotation at all — proposal [godotengine/godot-proposals#1230](https://github.com/godotengine/godot-proposals/issues/1230) is the long-standing request. For glTF import, Godot's [`gltf_document.cpp`](https://github.com/godotengine/godot/blob/master/modules/gltf/gltf_document.cpp) honors only the **base-color** texture's `KHR_texture_transform` and applies it to the whole material. This was the resolution of [godotengine/godot#27375](https://github.com/godotengine/godot/issues/27375): pragmatic, not spec-conformant.

### O3DE — Per-Material `float3x3` (with Inverse)

O3DE's StandardPBR material defines a dedicated `UvPropertyGroup.json` (<https://github.com/o3de/o3de/blob/development/Gems/Atom/Feature/Common/Assets/Materials/Types/MaterialInputs/UvPropertyGroup.json>) with:

- `Center` (default `[0.5, 0.5]`) — pivot
- `TileU`, `TileV` — per-axis tiling
- `OffsetU`, `OffsetV` — translation
- `Rotate` — degrees
- `Scale` — uniform

A `Transform2D` material functor compiles these into a `float3x3 m_uvMatrix` plus its inverse `m_uvMatrixInverse` (the inverse is needed for parallax / normal-mapping math). All primary maps (base color, normal, metallic, roughness) sample with the same UV. There is a separate `DetailMapsPropertyGroup` with its own UV transform, giving effectively two transforms per material — main and detail — but never per-slot.

References: <https://github.com/o3de/o3de/blob/development/Gems/Atom/Feature/Common/Assets/Materials/Types/StandardPBR.materialtype>, <https://docs.o3de.org/docs/atom-guide/look-dev/materials/material-system/>.

### Unity — `_ST` Convention (Per-Texture, Truly)

Unity is the engine that does it "right" for authored content. Every texture property automatically gets a paired `<TexName>_ST` `float4` (S = scale.xy in `.xy`, T = translation in `.zw`). The `TRANSFORM_TEX` macro in `UnityCG.cginc`:

```hlsl
#define TRANSFORM_TEX(tex, name) (tex.xy * name##_ST.xy + name##_ST.zw)
```

You call `TRANSFORM_TEX(IN.uv, _MainTex)` and `TRANSFORM_TEX(IN.uv, _BumpMap)` separately, so each texture has independent tiling/offset. No rotation in the standard convention (Shader Graph's Tiling-and-Offset node also lacks it natively). This is the convention `KHR_texture_transform` was modeled on.

References: <https://docs.unity3d.com/2019.3/Documentation/Manual/ShaderTut2.html>, <https://discussions.unity.com/t/how-to-get-the-textures-tiling-and-offset-variables/504558>.

### Unreal — Material Graph (Arbitrarily Per-Sample)

Unreal has no fixed-function tiling/offset attached to texture slots. The Material Editor's `TextureCoordinate` node, `Panner`, `Rotator`, and arbitrary math nodes let you wire any UV transform to any `TextureSample`. Per-texture transforms emerge from graph structure rather than being a dedicated feature. Datasmith's glTF importer does **not** support `KHR_texture_transform` per Epic's own forum responses (<https://forums.unrealengine.com/t/gltf-import-support-khr-texture-transform/263318>); third-party plugins fill the gap.

### Filament — `hasTextureTransforms` Flag

Filament's `gltfio` has a `MaterialKey::hasTextureTransforms` boolean (<https://github.com/google/filament/blob/main/libs/gltfio/src/MaterialProvider.cpp>). When true, the generated ubershader includes UV transform code, but historically per-material rather than per-slot. Issue [google/filament#2500](https://github.com/google/filament/issues/2500) was the original 2020 bug report; PR #2704 added support. Per-textureInfo correctness has been a recurring source of bugs.

### Bevy — `Affine2` Per Material

Bevy's `StandardMaterial.uv_transform` is a single `Affine2` applied to UV0 before all sampling (<https://docs.rs/bevy/latest/bevy/pbr/struct.StandardMaterial.html>). The doc string: "*The transform applied to the UVs corresponding to ATTRIBUTE_UV_0 on the mesh before sampling. Default is identity.*"

For glTF, Bevy uses the base-color `KHR_texture_transform` and applies it to every texture, **printing a warning** when other slots have different transforms. Issue [bevyengine/bevy#15310](https://github.com/bevyengine/bevy/issues/15310) tracks adding true per-texture support, blocked on the upstream `gltf-rs` crate.

## 4. Practical Considerations

### Storage form: `mat3` vs `mat4` vs `vec4`

| Form | Size | Captures | Used by |
|---|---|---|---|
| `vec4` (xy=scale, zw=offset) | 16 B | scale + translation only | Unity `_ST` |
| `mat3` (homogeneous 2D) | 36 B unpadded / 48 B with std140 padding | full affine (scale + rotate + translate + shear) | glTF spec, O3DE, Three.js |
| `mat4` (3D transform reused) | 64 B | full 3D affine; UV-relevant components only in 2×2 + 2-translation | none of the surveyed engines |

The strict-correct minimal form is `mat3`. `mat4` is wasteful — there's no Z-axis component for 2D UVs. It's also subtly hazardous: applying a 4×4 matrix to `float4(u, v, 0, 1)` requires the matrix to encode "rotation only around Z, no Z translation," which `MDLTransform.matrix` does not formally guarantee.

### Vertex vs fragment evaluation

- **Vertex-shader transform** (Godot's choice): one mat-vec per vertex, effectively free, but **only works when every fragment-shader sample uses the same UV**. Per-slot transforms break this — different slots want different transformed UVs at the same fragment.
- **Fragment-shader transform per slot** (the plan's choice): one mat3-vec3 per texture sample (5 mads). On modern GPUs, texture-sampling latency dwarfs the ALU cost. Genuinely cheap.

### Alternatives

- **Bake into the mesh's UV attribute at load**: works only if the mesh is uniquely-textured (can't share across two materials with different transforms) and only one transform per UV channel. Kills per-slot transforms by construction.
- **Bake into the source texture**: pre-compose during asset processing. Loses dynamic flexibility, zero runtime cost.
- **Identity-skip optimization**: most materials in practice have all-identity transforms. A `bool hasNonIdentityTransform` flag and a uniform branch (or shader variant) can skip the multiply entirely. Common in production engines.

### Per-slot in the wild

Common in glTF assets exported from Blender (separate Mapping nodes per Image Texture node), in texture-atlas workflows, and in tooling-driven content. Less common in hand-authored material packs from texture vendors, which is why Godot/Bevy's pragmatic shortcut is rarely visible to most users.

## 5. Verdict

The pattern "*capture per-texture transform from material import → bind to shader → multiply UVs before each sample*" is:

- **Spec-conformant** for both glTF (`KHR_texture_transform`) and USD (`UsdTransform2d`). USDZ specifically requires it for any asset using `UsdTransform2d`.
- **Implemented per-slot by**: Three.js, Babylon.js, PlayCanvas, UnityGLTF, the Khronos reference viewer, USD Hydra, Unity authored content via `_ST`.
- **Implemented as a single per-material transform by**: Godot, Bevy, Filament (historically), O3DE.

For a Metal renderer importing USDZ via ModelIO, the strict-correct per-slot approach is the right default. The only legitimate reasons to take the per-material shortcut are (a) the asset pipeline guarantees identical transforms per slot, or (b) measured shader-ALU pressure justifies the simplification — neither is plausible here.

## URLs Visited

### glTF `KHR_texture_transform`

- <https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_texture_transform>
- <https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Khronos/KHR_texture_transform/README.md>
- <https://gltf-transform.dev/modules/extensions/classes/KHRTextureTransform>
- <https://github.com/BabylonJS/Babylon.js/blob/c0e3f1480802513ac58fae99ab8307ae14120bd2/loaders/src/glTF/2.0/Extensions/KHR_texture_transform.ts>

### Godot

- <https://docs.godotengine.org/en/stable/classes/class_standardmaterial3d.html>
- <https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html>
- <https://github.com/godotengine/godot/blob/master/scene/resources/material.cpp>
- <https://github.com/godotengine/godot/blob/master/modules/gltf/gltf_document.cpp>
- <https://github.com/godotengine/godot/issues/27375>
- <https://github.com/godotengine/godot-proposals/issues/1230>

### O3DE

- <https://github.com/o3de/o3de/blob/development/Gems/Atom/Feature/Common/Assets/Materials/Types/StandardPBR.materialtype>
- <https://github.com/o3de/o3de/blob/development/Gems/Atom/Feature/Common/Assets/Materials/Types/MaterialInputs/UvPropertyGroup.json>
- <https://docs.o3de.org/docs/atom-guide/look-dev/materials/material-system/>
- <https://docs.o3de.org/docs/atom-guide/look-dev/materials/pbr/>

### Unity

- <https://docs.unity3d.com/2019.3/Documentation/Manual/ShaderTut2.html>
- <https://docs.unity3d.com/Packages/com.unity.shadergraph@6.9/manual/Tiling-And-Offset-Node.html>
- <https://discussions.unity.com/t/how-to-get-the-textures-tiling-and-offset-variables/504558>

### Unreal

- <https://forums.unrealengine.com/t/gltf-import-support-khr-texture-transform/263318>
- <https://dev.epicgames.com/documentation/en-us/unreal-engine/coordinates-material-expressions-in-unreal-engine>
- <https://dev.epicgames.com/documentation/en-us/unreal-engine/animating-uv-coordinates-in-unreal-engine>

### Filament

- <https://github.com/google/filament/issues/2500>
- <https://github.com/google/filament/blob/main/libs/gltfio/src/MaterialProvider.cpp>
- <https://github.com/google/filament/tree/main/libs/gltfio>

### Bevy

- <https://docs.rs/bevy/latest/bevy/pbr/struct.StandardMaterial.html>
- <https://github.com/bevyengine/bevy/issues/15310>

### USD / Apple ModelIO

- <https://openusd.org/dev/spec_usdpreviewsurface.html>
- <https://www.sidefx.com/docs/houdini/nodes/vop/usdtransform2d.html>
- <https://www.sidefx.com/docs/houdini/nodes/vop/usduvtexture.html>
- <https://developer.apple.com/documentation/modelio/mdltexturesampler>
- <https://developer.apple.com/documentation/modelio/mdltexturesampler/transform>
- <https://developer.apple.com/documentation/modelio/mdltransform>
- <https://developer.apple.com/documentation/modelio/mdlmaterialproperty>
- <https://metalbyexample.com/modelio-materials/>
- <https://github.com/metal-by-example/modelio-materials/blob/master/Shared/Renderer.swift>

### Performance & Baking

- <https://learnwebgl.brown37.net/10_surface_properties/texture_mapping_transforms.html>
- <https://forums.unrealengine.com/t/perf-cost-texture-object-texture-sample-vs-texture-object-texture-sample-2/737787>
