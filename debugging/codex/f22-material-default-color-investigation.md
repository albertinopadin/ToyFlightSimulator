# F22 Material Default-Color Leak Investigation

Date: 2026-04-15

## Summary

The F22 is not actually using the default `MaterialProperties.color` as its intended final color. What is happening is narrower:

1. The textured airframe submeshes import a base-color texture correctly, so they ignore the default color and render normally.
2. Several untextured F22 submeshes import their authored USD `baseColor` as `MDLMaterialPropertyType.float3`, but `Material.populateMaterial` does not copy `.float3` or `.float4` base colors into `properties.color`.
3. Transparent fragment shaders then fall back to `material.color`, which is still whatever global default was compiled into `MaterialProperties.init()`.
4. Under `CLEAR_COLOR`, some submeshes also get misclassified as transparent because `Material.isTransparent` uses `properties.color.w < 1.0`, and the loader left that alpha at the default value instead of replacing it with the authored material color.

That is why:

- `WHITE_COLOR` makes the canopy look white.
- `PINK_DEBUG_COLOR` makes the canopy look pink.
- `CLEAR_COLOR` makes the canopy effectively disappear and exposes cockpit/interior pieces.

The default color is leaking only where the importer failed to replace it with authored material data.

## What I Verified

### 1. The USD asset itself is authored correctly

Using `usdcat` on `ToyFlightSimulator Shared/Core/Resources/Models/Sketchfab/F-22_Raptor.usdz`, the asset contains:

- `f22a_airframe`: textured base color (`f22a-airframe_baseColor.jpg`)
- `Glass`: authored `diffuseColor = (1, 0.43825617, 0.06554228)`, `opacity = 0.6`
- `HudGlass`: authored `diffuseColor = (0.01094987, 0.28621072, 0)`, `opacity = 0.22439769`
- `f22a_landingLights`: authored `diffuseColor = (0.8, 0.8, 0.8)`

So the source asset already contains the material data that should replace the default color.

### 2. ModelIO imports those F22 materials, but not in the form the current loader expects

I inspected the loaded `MDLAsset` with a local Swift script. Relevant results:

```text
Object_0 / f22a_airframe
  baseColor: type = .texture, texture = f22a-airframe_baseColor.jpg

Object_1 / Glass
  baseColor: type = .float3, value = (1.0, 0.43825617, 0.06554228)
  opacity:   type = .float,  value = 0.6

Object_3 / HudGlass
  baseColor: type = .float3, value = (0.01094987, 0.28621072, 0.0)
  opacity:   type = .float,  value = 0.22439769

Object_7 / f22a_landingLights
  baseColor: type = .float3, value = (0.8, 0.8, 0.8)
```

This is the key detail: `Glass`, `HudGlass`, and `f22a_landingLights` are imported as `.float3` base colors, not `.color`.

### 3. The material loader drops those imported float3 colors

In [Material.swift](/Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/AssetPipeline/Material.swift:32), `populateMaterial(with:)` only assigns `properties.color` in the `.color` case:

```swift
case .color:
    let color = float4(Float(property.color!.components![0]),
                       Float(property.color!.components![1]),
                       Float(property.color!.components![2]),
                       Float(property.color!.components![3]))
    properties.color = color

case .float3:
    print("Material \(material.name) property is float3 for semantic: \(semantic.toString())")
    // base color, emission
```

Because `.float3` base colors are ignored, `properties.color` for those F22 submeshes remains whatever default value came from `MaterialProperties.init()`.

### 4. The current transparent shader path uses that stale default color as the fallback

The active default renderer is `TiledMSAATessellated`, which uses [TiledMSAATransparency.metal](/Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/TiledMSAATransparency.metal:18):

```metal
float4 color = material.color;

if (in.useObjectColor) {
    color = in.objectColor;
} else if (!is_null_texture(baseColorTexture)) {
    ...
}
```

For the F22 canopy and HUD glass:

- there is no base-color texture
- `useObjectColor` is false
- so the shader uses `material.color`
- but `material.color` was never replaced by the imported authored color

That directly explains the white and pink tinting.

### 5. `CLEAR_COLOR` also changes transparency classification for untextured materials

In [Material.swift](/Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/AssetPipeline/Material.swift:22), transparency is defined as:

```swift
return opacityTexture != nil || properties.opacity < 1.0 || properties.color.w < 1.0
```

If the default is `CLEAR_COLOR`, then `properties.color.w == 0` until the loader overrides it.

That causes an extra failure mode:

- `Glass` and `HudGlass` are already transparent because their authored `opacity` is below 1.
- `f22a_landingLights` has no authored opacity, but with `CLEAR_COLOR` it can still be treated as transparent only because the loader never replaced the default alpha.

This is why changing the global default color produces behavior changes that should have been impossible for imported materials.

## Why The Screenshots Behave The Way They Do

### `WHITE_COLOR`

- Canopy/HUD submeshes fall back to `material.color = (1, 1, 1, 1)`.
- The transparency shader then applies authored opacity:
  - canopy `Glass` becomes white with alpha `0.6`
  - HUD glass becomes white with alpha `0.22439769`
- The textured airframe still uses `f22a-airframe_baseColor.jpg`, so the body looks normal.

### `PINK_DEBUG_COLOR`

- Same exact bug path as above, but now `material.color = PINK_DEBUG_COLOR`.
- The canopy/HUD are tinted pink because the imported float3 base color was never copied into `properties.color`.

### `CLEAR_COLOR`

- For glass materials, the fallback becomes nearly-black transparent output:
  - start with `material.color = (0, 0, 0, 0)`
  - transparency shader raises alpha to authored opacity (`0.6` or `0.224...`)
  - RGB stays black
- Against the black skybox/background, the canopy appears to vanish.
- Any untextured material whose `properties.color` was never initialized away from clear can also get classified into the transparent path incorrectly because `properties.color.w < 1.0`.

The "missing top panels" in `ClearColorMat.png` are consistent with transparent or semi-transparent fallback on F22 submeshes that should have imported fixed authored material values instead of inheriting the global default.

## Root Cause

The bug is a combination of two issues:

### Root cause A: the importer ignores `.float3` / `.float4` base colors

This is the primary cause of the F22 canopy tinting bug.

`Glass`, `HudGlass`, and `f22a_landingLights` use untextured authored `baseColor`, but `Material.populateMaterial` never applies them to `properties.color`.

### Root cause B: some fragment shaders do not consistently fall back to `material.color`

This is a second bug that shows up once a material has no base-color texture.

For the active renderer:

- [TiledMSAATransparency.metal](/Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/TiledMSAATransparency.metal:18) does use `material.color` as a fallback.
- [TiledMSAAGBuffer.metal](/Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/TiledMSAAGBuffer.metal:21) does not initialize `color` from `material.color`.

Other shader variants have the same latent issue:

- [TiledDeferredGBuffer.metal](/Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredGBuffer.metal:97)
- [Base.metal](/Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/Base.metal:67)
- [SinglePassDeferredTransparency.metal](/Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/SinglePassDeferredTransparency.metal:44)

So the full fix should update both the loader and the shader fallback behavior.

## Recommended Fix

### 1. Import authored float3 / float4 base colors into `properties.color`

This is the essential fix for the F22 bug.

Suggested patch for [Material.swift](/Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/AssetPipeline/Material.swift:32):

```swift
private mutating func setBaseColor(from property: MDLMaterialProperty) {
    switch property.type {
        case .color:
            guard let components = property.color?.components, components.count >= 3 else { return }
            let alpha: Float = components.count > 3 ? Float(components[3]) : 1.0
            properties.color = float4(Float(components[0]),
                                      Float(components[1]),
                                      Float(components[2]),
                                      alpha)

        case .float3:
            let rgb = property.float3Value
            properties.color = float4(rgb.x, rgb.y, rgb.z, 1.0)

        case .float4:
            properties.color = property.float4Value

        default:
            break
    }
}
```

Then call it from `populateMaterial(with:)`:

```swift
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
                    let texture = TextureLoader.Texture(mdlTexture: sourceTexture)
                    populateTexture(texture, for: semantic)

                case .color, .float3, .float4:
                    if semantic == .baseColor {
                        setBaseColor(from: property)
                    }

                case .float:
                    if semantic == .opacity {
                        properties.opacity = property.floatValue
                    }

                case .buffer, .matrix44, .float2, .none:
                    break

                default:
                    break
            }
        }
    }
}
```

What this fixes:

- `Glass` and `HudGlass` stop inheriting the global default color.
- `f22a_landingLights` stops inheriting default alpha.
- `CLEAR_COLOR` no longer changes those imported materials, because the imported material color replaces the default.

### 2. Make opaque shader paths fall back to `material.color` too

This is needed so untextured opaque materials render deterministically instead of using uninitialized color.

Suggested patch for [TiledMSAAGBuffer.metal](/Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/TiledMSAAGBuffer.metal:21):

```metal
float4 color = material.color;

if (in.useObjectColor) {
    color = in.objectColor;
} else if (!is_null_texture(baseColorTexture)) {
    color = float4(baseColorTexture.sample(sampler2d, in.uv));
}
```

Apply the same fallback pattern to:

- `ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredGBuffer.metal`
- `ToyFlightSimulator Shared/Graphics/Shaders/Base.metal`
- `ToyFlightSimulator Shared/Graphics/Shaders/SinglePassDeferredTransparency.metal`

Without this second fix, untextured opaque materials can still render with undefined color even after the importer is corrected.

## Minimal Change Set

If you only want the minimum required changes for the F22 under the current default renderer:

1. Fix `Material.swift` so `.float3` / `.float4` base colors update `properties.color`.
2. Fix `TiledMSAAGBuffer.metal` so opaque untextured materials fall back to `material.color`.

That should remove the dependency on the global default material color for the F22 under `.TiledMSAATessellated`.

## Important Non-Fix

You should not need to change the default `MaterialProperties.init()` color in [MetalTypes.swift](/Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Core/Types/MetalTypes.swift:88). The default can stay pink, white, clear, or anything else for debugging. The real bug is that authored imported material values are not consistently overriding that default.
