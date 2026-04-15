# Fix: Material Default Color Bleeding Into F22 Canopy

## Problem

The F22's canopy, HUD glass, and landing lights render with whatever color is set in the `MaterialProperties()` no-arg init instead of their authored USD material colors. Changing the default color in `MetalTypes.swift:89` changes how these submeshes look, which should be impossible for correctly imported materials.

## Root Cause

Two issues working together:

1. **The material importer drops `.float3` / `.float4` base colors.** The F22 USD asset authors `Glass`, `HudGlass`, and `f22a_landingLights` as `.float3` base colors (verified via `usdcat`). But `Material.populateMaterial()` only writes to `properties.color` in the `.color` (CGColor) case. The `.float3` and `.float4` cases just print and do nothing, so `properties.color` stays as the default.

2. **GBuffer fragment shaders leave `color` uninitialized when no texture/objectColor exists.** The `VertexOut`-based GBuffer shaders (`TiledMSAAGBuffer`, `TiledDeferredGBuffer`, `Base.material_fragment`) declare `float4 color;` without initialization and only assign it inside `if` branches. When neither `useObjectColor` nor a texture applies, `color` is undefined. The transparency shaders handle this by falling back to `material.color`, but that value is wrong due to issue #1.

## Fix Strategy

**Part 1 - Material Importer**: Add a `setBaseColor(from:)` helper that handles `.color`, `.float3`, and `.float4` property types. Call it from `populateMaterial()` only for the `.baseColor` semantic. This ensures authored material colors always override the default.

**Part 2 - Shader Fallbacks**: Initialize `color` to `material.color` in all GBuffer/transparency fragment shaders that use `VertexOut`. Once Part 1 is correct, `material.color` becomes a reliable fallback.

No changes needed to `MaterialProperties()` default init, `isTransparent`, or `VertexOut`.

---

## Part 1: Fix Material Importer

### File: `Material.swift`

**Change A** - Add `setBaseColor(from:)` helper method (new function, add after `populateTexture`):

```swift
// BEFORE: (no such function exists)

// AFTER:
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

**Change B** - Update `populateMaterial()` to use `setBaseColor` for baseColor semantic and stop blindly assigning color for all semantics:

```swift
// BEFORE (lines 32-97):
private mutating func populateMaterial(with material: MDLMaterial) {
    for semantic in MDLMaterialSemantic.allCases {
        for property in material.properties(with: semantic) {
            switch property.type {
                case .string:
                    print("Material property is string!")
                    if let stringValue = property.stringValue {
                        print("Material property string value: \(stringValue)")
                        // TODO: This smells nasty
                        // Check if string is empty (WTF?)
                        let texture = TextureLoader.Texture(name: stringValue)
                        populateTexture(texture, for: semantic)
                    }
                case .URL:
                    print("Material property is url!")
                
                    if let textureURL = property.urlValue {
                        let texture = TextureLoader.Texture(url: textureURL)
                        populateTexture(texture, for: semantic)
                    }
                case .texture:
                    print("Material property is texture!")
                    let sourceTexture = property.textureSamplerValue!.texture!
                    let texture = TextureLoader.Texture(mdlTexture: sourceTexture)
                    populateTexture(texture, for: semantic)
                
                case .color:
                    print("Material property is color!")
                    
                    let color = float4(Float(property.color!.components![0]),
                                       Float(property.color!.components![1]),
                                       Float(property.color!.components![2]),
                                       Float(property.color!.components![3]))
                    
                    properties.color = color
                    
                case .buffer:
                    print("Material \(material.name) property is a buffer for semantic: \(semantic.toString())")
                case .matrix44:
                    print("Material \(material.name) property is 4x4 matrix for semantic: \(semantic.toString())")
                case .float:
                    print("Material \(material.name) property is float for semantic: \(semantic.toString())")
                    switch semantic {
                        case .opacity:
                            properties.opacity = property.floatValue
                            // ambient occlusion, ao scale, anisotropic rotation, clearcoat, clearcoat gloss,
                            // interface index of refraction, material index of refraction, none (WTF???),
                            // roughness, sheen, sheen tint, specular, specular tint, subsurface, 
                        default:
                            print("Property was not opacity")
                    }
                case .float2:
                    print("Material \(material.name) property is float2 for semantic: \(semantic.toString())")
                case .float3:
                    print("Material \(material.name) property is float3 for semantic: \(semantic.toString())")
                    // base color, emission
                case .float4:
                    print("Material \(material.name) property is float4 for semantic: \(semantic.toString())")
                case .none:
                    print("Material \(material.name) property is none for semantic: \(semantic.toString())")
                default:
                    fatalError("Data for material property not found - name: \(material.name), debug desc: \(material.debugDescription), for semantic: \(semantic.toString())")
            }
        }
    }
}

// AFTER:
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

**What this fixes**: `Glass` gets `properties.color = (1.0, 0.438, 0.066, 1.0)`, `HudGlass` gets `(0.011, 0.286, 0.0, 1.0)`, `f22a_landingLights` gets `(0.8, 0.8, 0.8, 1.0)`. The default color is no longer reachable for these submeshes.

---

## Part 2: Fix Shader Fallbacks

All `VertexOut`-based fragment shaders that determine `color` need a fallback for when neither `useObjectColor` nor a texture applies. The correct fallback is `material.color` (now reliable after Part 1).

### File: `TiledMSAAGBuffer.metal`

```metal
// BEFORE (lines 21-27):
    float4 color;
    
    if (in.useObjectColor) {
        color = in.objectColor;
    } else if (!is_null_texture(baseColorTexture)) {
        color = float4(baseColorTexture.sample(sampler2d, in.uv));
    }

// AFTER:
    float4 color = material.color;
    
    if (in.useObjectColor) {
        color = in.objectColor;
    } else if (!is_null_texture(baseColorTexture)) {
        color = float4(baseColorTexture.sample(sampler2d, in.uv));
    }
```

### File: `TiledDeferredGBuffer.metal`

```metal
// BEFORE (lines 97-103):
    float4 color;
    
    if (in.useObjectColor) {
        color = in.objectColor;
    } else if (!is_null_texture(baseColorTexture)) {
        color = float4(baseColorTexture.sample(sampler2d, in.uv));
    }

// AFTER:
    float4 color = material.color;
    
    if (in.useObjectColor) {
        color = in.objectColor;
    } else if (!is_null_texture(baseColorTexture)) {
        color = float4(baseColorTexture.sample(sampler2d, in.uv));
    }
```

### File: `Base.metal` (material_fragment, line 67)

```metal
// BEFORE (lines 67-73):
    float4 color;
    
    if (rd.useObjectColor) {
        color = rd.objectColor;
    } else if (!is_null_texture(baseColorMap)) {
        color = baseColorMap.sample(sampler2d, texCoord);
    }

// AFTER:
    float4 color = material.color;
    
    if (rd.useObjectColor) {
        color = rd.objectColor;
    } else if (!is_null_texture(baseColorMap)) {
        color = baseColorMap.sample(sampler2d, texCoord);
    }
```

### File: `SinglePassDeferredTransparency.metal` (line 44)

```metal
// BEFORE (lines 44-50):
    float4 color;
    
    if (in.useObjectColor) {
        color = in.objectColor;
    } else if (!is_null_texture(baseColorTexture)) {
        color = float4(baseColorTexture.sample(sampler2d, in.uv));
    }

// AFTER:
    float4 color = material.color;
    
    if (in.useObjectColor) {
        color = in.objectColor;
    } else if (!is_null_texture(baseColorTexture)) {
        color = float4(baseColorTexture.sample(sampler2d, in.uv));
    }
```

**Note**: `TiledDeferredTransparency.metal` and `TiledMSAATransparency.metal` already initialize `color = material.color`, so they need no change.

---

## Files Changed

| File | Change |
|---|---|
| `Material.swift` | Add `setBaseColor(from:)`, rewrite `populateMaterial()` |
| `TiledMSAAGBuffer.metal` | Initialize `color = material.color` |
| `TiledDeferredGBuffer.metal` | Initialize `color = material.color` |
| `Base.metal` | Initialize `color = material.color` in `material_fragment` |
| `SinglePassDeferredTransparency.metal` | Initialize `color = material.color` |

## Files NOT Changed

| File | Reason |
|---|---|
| `MetalTypes.swift` | Default color doesn't need to change; the bug is that imports don't override it |
| `ShaderDefinitions.h` | `VertexOut` doesn't need a vertex color field; `material.color` is the correct fallback |
| `TiledDeferredTransparency.metal` | Already uses `material.color` fallback |
| `TiledMSAATransparency.metal` | Already uses `material.color` fallback |

## Expected Results After Fix

- F22 canopy renders with authored `diffuseColor (1.0, 0.438, 0.066)` at opacity `0.6` (amber glass)
- HUD glass renders with authored `diffuseColor (0.011, 0.286, 0.0)` at opacity `0.224` (green-tinted)
- Landing lights render with authored `diffuseColor (0.8, 0.8, 0.8)` (light gray)
- Changing the default `MaterialProperties()` color has zero effect on any imported model
- The `CLEAR_COLOR` case no longer misclassifies submeshes as transparent

## Verification

1. Build and run with current default (`PINK_DEBUG_COLOR`) - canopy should be amber, not pink
2. Switch default to `WHITE_COLOR` - canopy should still be amber
3. Switch default to `CLEAR_COLOR` - canopy should still be amber, no missing panels
4. Verify textured submeshes (airframe body) still render normally
5. Verify objects using `setColor()`/`useObjectColor` (spheres, quad in scene) still render correctly
