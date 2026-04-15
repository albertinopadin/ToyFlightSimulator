# Material Color Bleeding Bug - Investigation Findings

## Summary

The default `MaterialProperties.color` (set in the no-arg `init()` at `MetalTypes.swift:88-96`) bleeds through to the F22's canopy and affects the visibility of other submeshes. The root cause is a chain of issues spanning the material loading pipeline, the `VertexOut` shader struct, the transparency fragment shaders, and the `isTransparent` classification logic.

## Observed Behavior

| Default Color | Canopy | Top Panels | Body |
|---|---|---|---|
| `WHITE_COLOR [1,1,1,1]` | White tinted | Normal | Normal |
| `PINK_DEBUG_COLOR [1,0,0.765,1]` | Pink tinted | Normal | Normal |
| `CLEAR_COLOR [0,0,0,0]` | Invisible | Some missing | Normal |

## Root Cause Chain

### Step 1: F22 canopy material has opacity < 1.0

The F22 model's canopy submesh has an MDLMaterial with `opacity < 1.0`. This causes `Material.isTransparent` to return `true`, sending the canopy through the **transparency rendering path** instead of the GBuffer/deferred path.

### Step 2: `properties.color` is never overwritten for some submeshes

In `Material.swift:12`, properties are initialized with the no-arg `MaterialProperties()`:

```swift
// Material.swift:12
public var properties = MaterialProperties()
```

The no-arg init uses the default color (`MetalTypes.swift:88-96`):

```swift
// MetalTypes.swift:88-96
init() {
    self.init(color: PINK_DEBUG_COLOR,   // <-- THIS IS THE BUG SOURCE
              ambient: [0.1, 0.1, 0.1],
              diffuse: [1, 1, 1],
              specular: [1, 1, 1],
              shininess: 2.0,
              opacity: 1.0,
              isLit: true)
}
```

Then `setProperties()` runs and puts the baseColor semantic into `properties.diffuse`, **NOT** `properties.color`:

```swift
// Material.swift:133-137
case .baseColor:
    let diffuse = materialProp.float3Value
    if diffuse != .zero {
        properties.diffuse = diffuse  // Sets DIFFUSE, not COLOR
    }
```

Then `populateMaterial()` runs and iterates all semantics. It only sets `properties.color` when a property has `.color` TYPE (i.e., is stored as a CGColor):

```swift
// Material.swift:58-66
case .color:
    let color = float4(...)
    properties.color = color  // Only runs if property TYPE is .color
```

If the canopy's MDLMaterial doesn't have any properties stored as CGColor type (many materials use textures, strings, or floats instead), `properties.color` **retains the default** from the no-arg init.

### Step 3: `VertexOut` struct lacks vertex color

The `VertexOut` struct used by transparency shaders (`ShaderDefinitions.h:78-90`) does NOT carry vertex color:

```metal
// ShaderDefinitions.h:78-90
struct VertexOut {
    float4 position [[ position ]];
    float3 normal;
    float2 uv;
    float3 worldPosition;
    float3 worldNormal;
    float3 worldTangent;
    float3 worldBitangent;
    float4 shadowPosition;
    uint instanceId;
    float4 objectColor;
    bool useObjectColor;
    // NOTE: No vertex color field!
};
```

Compare with `ColorInOut` used by GBuffer shaders (`GBuffer.metal:24-36`), which DOES have `float4 color`:

```metal
// GBuffer.metal:24-36
typedef struct {
    float4 position [[ position ]];
    float4 color;          // <-- Has vertex color
    float4 objectColor;
    float2 tex_coord;
    // ...
} ColorInOut;
```

### Step 4: Transparency shaders fall back to `material.color`

The transparency fragment shaders start with `material.color` as the base and only override it if there's a texture or objectColor:

```metal
// TiledDeferredTransparency.metal:44-50
float4 color = material.color;  // <-- DEFAULT IS material.color

if (in.useObjectColor) {
    color = in.objectColor;
} else if (!is_null_texture(baseColorTexture)) {
    color = float4(baseColorTexture.sample(sampler2d, in.uv));
}
// If neither condition is true, output IS material.color
```

The GBuffer shader handles this correctly by falling back to vertex color:

```metal
// GBuffer.metal:123-129
if (in.useObjectColor) {
    base_color_sample = half4(in.objectColor);
} else if (!is_null_texture(baseColorMap)) {
    base_color_sample = baseColorMap.sample(sampler2d, in.tex_coord.xy);
} else {
    base_color_sample = half4(in.color);  // <-- Falls back to VERTEX color
}
```

### Step 5: `isTransparent` depends on `properties.color.w`

```swift
// Material.swift:22-24
public var isTransparent: Bool {
    return opacityTexture != nil || properties.opacity < 1.0 || properties.color.w < 1.0
}
```

With `CLEAR_COLOR [0,0,0,0]`, `properties.color.w = 0.0`, causing **all** submeshes with default (un-overwritten) color to be classified as transparent. This explains why top panels disappear with `CLEAR_COLOR` - they get reclassified as transparent and rendered with `[0,0,0,0]` making them invisible.

### Additional Issue: `populateMaterial()` color assignment is semantic-agnostic

```swift
// Material.swift:33-66
for semantic in MDLMaterialSemantic.allCases {
    for property in material.properties(with: semantic) {
        switch property.type {
            case .color:
                properties.color = color  // Sets for ANY semantic, not just baseColor!
```

If multiple semantics (e.g., emission, opacity, baseColor) have `.color` type properties, the **last one processed wins**, regardless of which semantic it belongs to.

### Additional Issue: `single_pass_deferred_transparency_fragment` has uninitialized color

```metal
// SinglePassDeferredTransparency.metal:44-50
float4 color;  // UNINITIALIZED

if (in.useObjectColor) {
    color = in.objectColor;
} else if (!is_null_texture(baseColorTexture)) {
    color = float4(baseColorTexture.sample(sampler2d, in.uv));
}
// No else! 'color' is garbage if neither condition is true
```

## Affected Files

| File | Lines | Issue |
|---|---|---|
| `MetalTypes.swift` | 88-96 | Default color used as fallback |
| `Material.swift` | 12 | `properties` initialized with default color |
| `Material.swift` | 22-24 | `isTransparent` depends on `properties.color.w` |
| `Material.swift` | 58-66 | Semantic-agnostic color assignment |
| `Material.swift` | 133-137 | baseColor goes to `diffuse` not `color` |
| `ShaderDefinitions.h` | 78-90 | `VertexOut` missing vertex color field |
| `TiledDeferredTransparency.metal` | 13-37 | Vertex shader doesn't pass vertex color |
| `TiledDeferredTransparency.metal` | 44 | Fragment uses `material.color` as fallback |
| `TiledMSAATransparency.metal` | 18 | Same `material.color` fallback |
| `SinglePassDeferredTransparency.metal` | 44 | Uninitialized color variable |

## Affected Renderers

All three transparency pipelines are affected:
- **TiledDeferred** + **TiledMSAA** + **TiledMSAATessellated**: Use `tiled_deferred_transparency_fragment` (confirmed in `TiledMSAAPipeline.swift:103-104`)
- **SinglePassDeferred**: Uses `single_pass_deferred_transparency_fragment` (uninitialized color bug)

## Proposed Fix

The fix addresses all four root cause issues:

### Fix 1: Add vertex color to `VertexOut` and transparency vertex shaders

**ShaderDefinitions.h** - Add `color` field to `VertexOut`:

```metal
struct VertexOut {
    float4 position [[ position ]];
    float4 color;             // ADD: vertex color
    float3 normal;
    float2 uv;
    float3 worldPosition;
    float3 worldNormal;
    float3 worldTangent;
    float3 worldBitangent;
    float4 shadowPosition;
    uint instanceId;
    float4 objectColor;
    bool useObjectColor;
};
```

**TiledDeferredTransparency.metal** - Pass vertex color in vertex shader:

```metal
vertex VertexOut
tiled_deferred_transparency_vertex(VertexIn                in              [[ stage_in ]],
                                   constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                   constant ModelConstants *modelConstants [[ buffer(TFSBufferModelConstants) ]],
                                   constant LightData      &lightData      [[ buffer(TFSBufferDirectionalLightData) ]],
                                   uint                    instanceId      [[ instance_id ]]) {
    ModelConstants modelInstance = modelConstants[instanceId];
    float4 worldPosition = modelInstance.modelMatrix * float4(in.position, 1);
    float4 position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition;

    VertexOut out {
        .position = position,
        .color = in.color,             // ADD: pass vertex color through
        .normal = in.normal,
        .uv = in.textureCoordinate,
        .worldPosition = worldPosition.xyz / worldPosition.w,
        .worldNormal = modelInstance.normalMatrix * in.normal,
        .worldTangent = modelInstance.normalMatrix * in.tangent,
        .worldBitangent = modelInstance.normalMatrix * in.bitangent,
        .shadowPosition = lightData.shadowViewProjectionMatrix * worldPosition,
        .instanceId = instanceId,
        .objectColor = modelInstance.objectColor,
        .useObjectColor = modelInstance.useObjectColor
    };
    return out;
}
```

Apply the same change to `single_pass_deferred_transparency_vertex` in `SinglePassDeferredTransparency.metal`.

### Fix 2: Use vertex color as fallback in transparency fragment shaders

**TiledDeferredTransparency.metal** - Change fragment shader:

```metal
fragment float4
tiled_deferred_transparency_fragment(VertexOut                   in                  [[ stage_in ]],
                                     constant MaterialProperties &material           [[ buffer(TFSBufferIndexMaterial) ]],
                                     sampler                     sampler2d           [[ sampler(0) ]],
                                     texture2d<half>             baseColorTexture    [[ texture(TFSTextureIndexBaseColor) ]]) {
    float4 color;

    if (in.useObjectColor) {
        color = in.objectColor;
    } else if (!is_null_texture(baseColorTexture)) {
        color = float4(baseColorTexture.sample(sampler2d, in.uv));
    } else {
        color = in.color;  // CHANGED: fall back to vertex color, not material.color
    }

    if (color.a < 1.0 && material.opacity < 1.0) {
        color.a = max(color.a, material.opacity);
    } else {
        color.a = min(color.a, material.opacity);
    }

    return color;
}
```

Apply the same pattern to `TiledMSAATransparency.metal` and `SinglePassDeferredTransparency.metal`.

### Fix 3: Fix `Material.setProperties()` to set `properties.color` from baseColor

**Material.swift** - Update `setProperties()`:

```swift
case .baseColor:
    let diffuse = materialProp.float3Value
    if diffuse != .zero {
        properties.diffuse = diffuse
        properties.color = float4(diffuse, properties.color.w)  // ADD: also set color
    }
```

### Fix 4: Restrict `populateMaterial()` color assignment to baseColor semantic

**Material.swift** - Only set color for baseColor semantic:

```swift
case .color:
    print("Material property is color!")
    let color = float4(Float(property.color!.components![0]),
                       Float(property.color!.components![1]),
                       Float(property.color!.components![2]),
                       Float(property.color!.components![3]))

    if semantic == .baseColor {  // ADD: only set for baseColor semantic
        properties.color = color
    }
```

### Fix 5: Remove `properties.color.w` from `isTransparent` check

**Material.swift** - Transparency should not depend on potentially-unset default color:

```swift
public var isTransparent: Bool {
    return opacityTexture != nil || properties.opacity < 1.0
}
```

## Verification

After applying the fixes:
1. The canopy should render using vertex colors when no texture exists, matching the rest of the aircraft
2. Changing the default `MaterialProperties` color should have no effect on model rendering
3. Top panels should remain opaque regardless of the default color's alpha
4. Transparent submeshes should still blend correctly using `material.opacity`
