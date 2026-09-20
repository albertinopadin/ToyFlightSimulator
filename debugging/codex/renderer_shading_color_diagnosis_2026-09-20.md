# Renderer shading and color differences — diagnosis and repair pseudocode

**Date:** 2026-09-20 · **Agent:** Codex  
**Source snapshot:** `320fec4` (current checkout when inspected)  
**Scope:** Diagnose the supplied screenshots and describe fixes. No rendering code was changed.

## 1. Findings

The renderers do not currently implement the same lighting model. Their differences are large enough to explain the screenshots without assuming broken shadow maps or a display gamma problem.

| Renderer | Confirmed behavior in its active shaders | Consequence |
|---|---|---|
| Tiled deferred | Computes direct diffuse light only. There is no additive ambient light; scene ambient and diffuse intensity controls are ignored. | Faces perpendicular to or facing away from the sun become black. |
| Tiled deferred MSAA | Uses the same G-buffer and directional lighting functions as tiled deferred. | Same lighting defect; multisampling changes edge coverage, not the lighting equation. |
| Tiled MSAA tessellated | Ordinary meshes use the same functions as the other two tiled renderers. | Same defect on the aircraft, structures, and ordinary ground quad. Tessellated terrain has additional issues discussed separately. |
| Single-pass deferred | Mixes world-space normals with eye-space lighting vectors, narrows scale-bearing normals to half precision, imposes a diffuse floor, and adds broad, strong, albedo-colored specular highlights. | Camera-dependent shading errors, invalid normals on very large geometry, bright patches, clipped colors, and an artificial transition between lit and unlit faces. |
| Order-independent transparency (OIT) | Both its opaque material shader and transparent material shader have their lighting code commented out. | Constant-color objects look like flat silhouettes; textures provide the aircraft's remaining surface detail. Its lack of cast shadows is expected. |

Additional confirmed inconsistencies affect particular materials: deferred transparent surfaces are unlit; single-pass opaque and OIT transparent surfaces use vertex color where other material paths use material color; normal-map handedness differs; some model transforms do not update normals correctly. These are distinct from the main causes above.

### Evidence and limits

- Visually inspected [TiledDeferredColors.png][shot-tiled], [SinglePassDeferredColors.png][shot-single], and [OIT_Colors.png][shot-oit].
- Traced renderer → pipeline state → shader → material/light inputs in current source, including animated variants. Findings below cite the actual functions and line locations.
- Independently evaluated the lighting equations, camera-space example, half-precision range, nonuniform-scale example, shadow remapping, and sRGB example using ephemeral Python scratch calculations. These are arithmetic checks, not executed GPU tests.
- No application run, Xcode build, GPU capture, or Xcode test suite was performed. A screenshot cannot establish the precise material and shader inputs of an individual pixel. No claim below attributes a specific screenshot pixel value to an exact calculation.
- Renderer switches rebuild the scene, and this scene generates random objects. The screenshots also have different headings/object arrangements. Compare fixed calibration geometry when validating the eventual changes.
- Other agents' pre-existing debugging documents and scripts were left untouched and were not used as evidence for this diagnosis.

## 2. Terms and conventions

- **Albedo / base color:** the surface's color before illumination. Multiplying it by a light contribution produces reflected diffuse color.
- **Normal:** a direction perpendicular to the surface. A unit normal has length one.
- **Diffuse lighting:** broad illumination depending on the angle between the normal and direction toward a light.
- **Ambient lighting:** a cheap approximation to indirect light arriving from the surroundings. Here the proposed baseline is a constant ambient contribution, not a simulation of reflected light.
- **Specular lighting:** a view-dependent reflection highlight. Its strength and its exponent are different controls: strength changes brightness; exponent changes highlight width.
- **G-buffer:** intermediate per-pixel surface information used by a later lighting stage.
- **World space:** the scene's coordinates. **Eye/view space:** coordinates relative to the current camera. Vectors in a dot product must use the same space.
- **Visibility:** fraction of direct sunlight reaching a surface, from zero (blocked) to one (unblocked). The existing shadow helper returns a remapped value instead.
- **Linear RGB:** color values suitable for lighting arithmetic. **sRGB:** a nonlinear storage/display encoding. Opacity and geometric data are not sRGB colors.
- **Tangent basis:** tangent, bitangent, and normal directions that orient a normal-map sample on the surface.

All pseudocode uses column-vector transforms. The engine is left-handed, +Y is up, and +Z is forward. `light.direction` points **from the surface toward the sun**, so diffuse illumination uses the positive dot product with that direction. Positions are in world meters where specified; normalized directions, color values, visibility, and the existing light controls are dimensionless. The controls are artistic scales, not calibrated physical radiometric units.

## 3. The active paths

| Family | Geometry / material function | Lighting function | Source of wiring |
|---|---|---|---|
| Tiled deferred | `tiled_deferred_gbuffer_fragment` | `tiled_deferred_directional_light_fragment` | [TiledDeferredPipeline.swift][pipeline-tiled] |
| Tiled MSAA, including the tessellated renderer's ordinary meshes | **Also** `tiled_deferred_gbuffer_fragment` | **Also** `tiled_deferred_directional_light_fragment` | [TiledMSAAPipeline.swift, lines 46–85][pipeline-msaa] |
| Single-pass deferred | `gbuffer_fragment_material` | `deferred_directional_lighting_fragment` | [SinglePassDeferredPipeline.swift][pipeline-single] |
| OIT opaque | `material_fragment` | Lighting would happen inside the same function, but is disabled | [OITRenderer.swift, lines 84–118][oit-renderer], [OrderIndependentTransparencyPipeline.swift][pipeline-oit] |
| OIT transparent | `transparent_material_fragment` | Lighting would happen before storing the fragment, but is disabled | [OrderIndependentTransparencyPipeline.swift][pipeline-oit] |

`TiledMSAAGBuffer.metal` and `TiledMSAATransparency.metal` contain separately registered shader functions, but the active MSAA pipeline selects the **TiledDeferred** functions. Fixing only those MSAA-named files will not fix the current rendering. The inactive transparency function's multisampled material-texture handling is therefore not a cause of these screenshots.

The scene already sets the sun's brightness to `1`, ambient intensity to `0.4`, and diffuse intensity to `0.5`. See [FlightboxWithPhysics.swift, lines 171–178][scene]. A missing CPU-side ambient setting is not the problem.

## 4. Why the tiled renderers have black sides

### 4.1 The shader contains no ambient addition

[TiledDeferredDirectionalLight.metal, lines 19–37][tiled-light] constructs a temporary material, sets `shininess = 0.1` and `ambient = 1`, then calls [Lighting.CalculateDirectionalLighting, lines 62–72][lighting-directional]. The helper interprets those fields as metallic amount and ambient occlusion respectively.

For the current one-sun path, the combined calculation is:

```pseudocode
diffuseCosine = max(dot(worldNormal, worldDirectionTowardSun), 0)
diffuseColor = baseColorLinear * (1 - 0.1) * diffuseCosine * sunColorLinear
outputColorLinear = diffuseColor * storedShadowFactor
```

Despite the field name, `material.ambient = 1` is only a multiplier inside the direct-light term. Multiplying zero by one cannot illuminate a dark face. The function never adds `light.ambientIntensity`; it also ignores `light.brightness` and `light.diffuseIntensity`.

This matches the screenshot: rounded objects have colored upper regions and black lower regions, while vertical structures nearly disappear. The configured sun is nearly overhead, making vertical faces especially susceptible. This is a lighting omission, not evidence that every black face is inside a cast shadow.

### 4.2 Shininess is incorrectly treated as metallic amount

`material.shininess` is used elsewhere as a highlight exponent; its default is `2` in [MetalTypes.swift][metal-types]. A metallic fraction is a separate quantity normally constrained to `[0,1]`. Using `1 - shininess` makes `shininess = 1` remove diffuse illumination entirely. The comment about that producing black output in the tiled shader documents the consequence of this semantic mix-up.

The temporary value `0.1` currently just dims every tiled diffuse result by a factor of `0.9`. The tiled shader computes no corresponding metal reflection or specular term. It is not a functioning metallic material model.

**Fix:** remove this reinterpretation from the basic diffuse model. A future physically based material system can give metallic amount its own field and reflection model.

### 4.3 Shadow brightness is doing a different job from ambient light

[TiledDeferredGBuffer.metal, lines 101–110][tiled-gbuffer] stores the shadow result in **albedo alpha**. This is an opaque G-buffer convention, not opacity. The lighting pass multiplies all its direct diffuse light by that channel.

[Lighting.CalculateShadow, lines 159–210][lighting-shadow] computes filtered visibility but returns:

```pseudocode
storedShadowFactor = 0.5 + 0.5 * sunlightVisibility
```

Thus an otherwise lit surface retains half its direct illumination in full shadow. A face with zero diffuse cosine remains black, even with that shadow floor. This explains how the screenshot can contain moderately dark cast shadows and completely black sides at the same time.

**Fix:** use real visibility for direct lighting and an independent additive ambient term. Change both the helper's return contract and its consumers together; just changing the final `0.5` would make the current renderer darker.

### 4.4 Shared repair

The simplest repair needs no new material attachments: use the existing albedo, normal, and shadow channels and the already supplied sun settings. Section 8 gives the common equation and integration pseudocode. All three tiled renderers receive that repair through the shared active shaders.

## 5. Why single-pass deferred looks harsh and overly intense

### 5.1 Its normals and lighting vectors are in different coordinate spaces

The data flow is unambiguous:

1. [GameObject.update, line 87][gameobject] builds `normalMatrix` from the object's **world** model matrix.
2. [GBuffer.metal, lines 45–66 and 90–103][single-gbuffer] uses that matrix for `normal`, `tangent`, and `bitangent`. There is no multiplication by the view transform. The names and comments describing them as eye-space are inaccurate.
3. [LightManager.GetDirectionalLightData, lines 54–62][lights] does transform the sun direction into eye space. The scene supplies `skyViewMatrix`, which is the view matrix with translation removed; this is appropriate for a direction.
4. [DirectionalLight.metal, lines 50–79][single-light] takes dot products between the stored **world normal** and **eye-space** sun/halfway directions. The reconstructed fragment position and camera direction are also eye-space.

This is a correctness defect even when a near-identity camera orientation makes it appear acceptable. Turning the camera changes the light vector's coordinate representation while leaving the normal's representation unchanged.

**Worked example:** a surface normal and sun direction both equal world `[0,1,0]`. Their correct diffuse cosine is one. Rotate the view basis by 60 degrees about X: the current mixed-space dot product becomes `0.5`; rotating both vectors keeps it at `1`. At 90 degrees, the incorrect dot product approaches zero and the shader's artificial `0.4` floor takes over. This was reproduced numerically.

**Fix:** keep this renderer's existing eye-space position reconstruction and make the G-buffer normal genuinely eye-space. Preserve a separate world normal for shadow bias. Do this in both static and animated vertex paths. Section 8 describes an especially clear version: resolve the mapped normal in world space, then rotate it into eye space before storing it.

There is also a **precision failure before the fragment even receives this normal**. `ColorInOut.normal`, `tangent`, and `bitangent` are `half3`. The vertex shaders cast the unnormalized model-transformed directions to half precision. The actual scene's `groundSize` is `1,000,000`, and `addGround` applies it as uniform model scale. With the current normal-matrix helper, a unit ground normal therefore has magnitude approximately `1,000,000` before that cast. The largest finite binary16 value is `65,504`; the input cannot be represented as a finite half value. Subsequent normalization is not a sound way to recover the original direction from overflowed inputs. The exact resulting pixel behavior depends on GPU/compiler handling and was not captured here.

**Supporting fix:** keep basis transforms/interpolation in `float3` for the simple version, normalize safely in float, and narrow only a bounded unit normal when storing the G-buffer. Alternatively, normalize in float before narrowing a vertex varying, then normalize again in float after interpolation. Fixing the normal matrix alone is not sufficient justification for unnormalized half math: the inverse-transpose of a million-scale transform produces directions near `0.000001`, whose squared length can underflow in half arithmetic. The single-pass ground must be part of the validation scene.

### 5.2 A diffuse floor replaces ambient lighting

[DirectionalLight.metal, lines 53–59][single-light] computes:

```pseudocode
diffuseCosine = max(dot(storedNormal, eyeDirectionTowardSun), 0)
diffuseCosine = max(diffuseCosine, 0.4)
diffuseColor = baseColorLinear * diffuseCosine * sunColorLinear
```

The `0.4` is hardcoded; it is not read from the scene's `ambientIntensity`. Brightness and diffuse intensity are ignored here too. A minimum on diffuse lighting is not the same as ambient **plus** diffuse: all faces below the threshold have the same diffuse illumination, and the slope changes abruptly at the threshold. The shader later shadows this floor along with everything else.

**Fix:** remove the floor and use the same additive ambient/direct diffuse equation as the tiled and OIT paths.

### 5.3 Specular strength and exponent are confused

The same shader uses `lightData.specularIntensity` as the exponent of the normal/halfway-vector dot product. The scene never changes the default of `1` in [MetalTypes.swift, lines 109–125][metal-types]. An exponent of one creates a very broad highlight. The local variable named `shininess` is just a multiplier equal to one, rather than the material's exponent.

[GBuffer.metal, lines 186–192][single-gbuffer] sets specular contribution to `1` when the material has no usable specular map, including object-color overrides. Then the light shader multiplies the highlight by the diffuse base color again:

```pseudocode
highlight = max(dot(storedNormal, eyeHalfwayDirection), 0) ^ 1
specularColor = highlight * baseColorLinear * storedSpecularStrength * sunColorLinear
```

Consequences:

- Most ordinary colored objects receive strong highlights even if they should look matte.
- Colored highlights reinforce the base hue. This is not a suitable default for ordinary nonmetallic surfaces, whose reflection color should be a separate material property.
- There is no front-lit gate for specular, so it can contribute where direct lighting should be rejected.
- Setting `specularIntensity` to zero would not reliably disable specular: a positive dot product raised to zero becomes one. The zero-to-zero case of `powr` is also problematic. Strength must multiply the result.

**Worked examples:** `0.8^1 = 0.8`, while `0.8^32 ≈ 0.000792282`. For a base-color channel of `0.7`, diffuse cosine `0.8`, halfway cosine `0.8`, and specular strength `1`, the current unshadowed result is `0.7 × (0.8 + 0.8) = 1.12`.

All active lighting destinations currently use normalized 8-bit color formats. Values above one cannot be preserved there, so this example clips to one before the final copy. This loses highlight variation and changes channel ratios when channels clip at different times. The calculations demonstrate a real clipping mechanism; they do not prove which aircraft screenshot pixels clipped.

**Fix:** first disable specular in every family to establish diffuse/ambient parity. Then restore it as a separate, explicitly controlled term with a material exponent, independent reflectance/strength, and a front-lit gate. Do not turn up scene brightness to compensate for the original mistakes.

### 5.4 A second shadow adjustment compounds the inconsistency

The shared shadow helper already maps visibility to `[0.5,1]`. [DirectionalLight.metal, lines 83–92][single-light] then adds `0.1`, clamps, and multiplies **both diffuse and specular** by the result.

| Filtered sun visibility | Tiled multiplier | Single-pass multiplier |
|---:|---:|---:|
| 0 | 0.50 | 0.60 |
| 0.5 | 0.75 | 0.85 |
| 1 | 1.00 | 1.00 |

This is a different shadow response from the tiled renderers. With real visibility and an independent ambient contribution, both remappings can be removed. Keep the existing cascade selection, filtering, bias, and cascade blending.

## 6. Why OIT looks flat

### 6.1 Opaque objects are also unlit

OIT describes how overlapping transparent fragments are combined; it does not require flat shading.

[OITRenderer.swift][oit-renderer] draws opaque meshes with `.OpaqueMaterial`, which selects [Base.material_fragment][base]. That function resolves the base color and returns it directly. The lighting block at lines 118–136 is commented out. It computes a normal for a second output, but no subsequent lighting stage uses that normal to shade OIT's main color target.

So an opaque sphere with one color has essentially that same color across its visible surface. The aircraft looks flat because its visible patterns are primarily in its texture rather than coming from evaluated light.

### 6.2 Transparent objects are also unlit

[OrderIndependentTransparency.transparent_material_fragment, lines 82–115][oit-shader] similarly resolves the base color, leaves its lighting block commented out, resolves opacity, and premultiplies RGB by alpha before insertion into the image block. The final blending loop combines these unlit colors.

**Fix:** compute lit **straight RGB** first, then premultiply once by opacity and use the existing insertion/blending algorithm. Use sun visibility equal to one for OIT; it can have normal-based diffuse and specular shading without cast shadows.

### 6.3 Do not simply uncomment the old lighting code

[Lighting.GetPhongIntensity, lines 18–59][lighting-phong] has its own inconsistent model:

- Computes light direction from `light.position - worldPosition` even for a directional sun. This makes its direction vary across the scene.
- Forces diffuse cosine to at least `0.3`, then adds ambient only when the unclamped diffuse cosine is zero. That introduces a discontinuity.
- The material importer copies base-color information into `material.diffuse`; multiplying its returned intensity by resolved base color can apply the color twice for affected materials.
- [Material.swift, lines 186–208][material] puts emission data into `ambient`. Emission and ambient reflection are different concepts.
- The disabled opaque block references `material.useNormalMapTexture`, which is no longer present in `MaterialProperties`.

Those defects could produce dark or inconsistent results if restored, but the old TODO comments do not prove which one caused the historical problem. Replace the active lighting calculation with the shared baseline; keep the old helper clearly marked as legacy if retaining it for learning.

## 7. Other color and normal inconsistencies

### 7.1 Material-color fallback is not consistent

[ShaderHelpers.ResolveBaseColor][helpers] follows object override → texture → caller-supplied fallback. The helper itself is consistent; callers disagree:

| Active material path | Fallback if no object override and no base-color texture |
|---|---|
| Tiled opaque | `material.color` |
| Single-pass opaque | `in.color` (interpolated vertex color) |
| OIT opaque | `material.color` |
| OIT transparent | `rd.color` (interpolated vertex color) |
| Deferred transparent | `material.color` |

A textureless imported material can therefore change color when the renderer changes, even after all lighting equations agree. This is conditional on the material and mesh data; the screenshots alone do not identify such a submesh.

**Fix:** make material fragments consistently use `material.color` as their fallback. Retain a clearly explicit vertex-color mode for geometry whose colors are intentionally stored per vertex; the existing base-only shaders can remain a separate vertex-color path. Do not silently replace authored vertex colors everywhere.

[DrawManager.drawSubmeshes, lines 579–585][draw-material] also skips all material binding when `submesh.material` is absent. That can leave the previous draw's textures/constants bound. Bind an explicit fallback material, identity UV transforms, and null material textures for that case. This is an additional conditional defect, not established as the cause of the supplied images.

### 7.2 Deferred transparency still bypasses lighting

[TiledDeferredTransparency.metal][transparent-tiled] and [SinglePassDeferredTransparency.metal][transparent-single] output base color and opacity directly. The MSAA pipelines use the former too. As a result, transparent and opaque parts of an aircraft can have visibly different illumination.

They need forward lighting in their transparency shaders using the same shared equation. Provide the required light, scene, normal-map, and optional shadow inputs. The scenes already bind directional constants and scene constants; the shader interfaces must consume the appropriate data.

There is also a separate animated-transparency wiring error: [RenderPipelineStateLibrary.animatedVariant, lines 80–83][animated-variants] maps tiled transparency to the **animated G-buffer pipeline**. Those pipelines write G-buffer attachments instead of blended lit color, and transparency runs after directional lighting. Attachment compatibility alone does not make the fragment behavior correct.

**Fix:** add actual tiled animated transparency pipeline variants, pairing the existing skinned geometry output with the transparency fragment function and appropriate alpha blending. Register/map them separately for 1× and 4× sample counts. Preserve `DrawManager`'s existing pass-PSO restoration. This affects skinned transparent submeshes specifically, not every black opaque side.

### 7.3 Normal transforms need two supporting repairs

**Nonuniform scale:** [Transform.normalMatrix, lines 64–69][transform] returns the model matrix's upper-left 3×3 directly. A normal generally needs the inverse transpose of that matrix. Normalizing afterward only fixes the magnitude, not the direction. The current shortcut works for rotations with uniform scale, but fails for slanted normals under unequal scale or hierarchy-induced shear.

For scale `[2,1,1]` and local normal proportional to `[1,1,0]`, the current normalized result is `[0.894427,0.447214,0]`; the correct result is `[0.447214,0.894427,0]`. Its dot product with a corresponding transformed tangent is `0.6` for the current result and `0` for the correct result. This was reproduced numerically. Axis-aligned box faces can escape this particular error.

**Mesh-local transforms:** [DrawManager.writeTransformedUniforms, lines 528–531][draw-transforms] and the legacy `Draw` path multiply `modelMatrix` by a mesh-local transform but keep the old `normalMatrix`. Rotating an animated control surface can therefore move its geometry without equivalently rotating its lighting normal.

**Fix:** compute the normal matrix from the final combined transform in both paths. Tangents and bitangents are surface directions; transform them with the combined model linear matrix, then orthogonalize against the transformed normal. Do not blindly keep using the inverse-transpose normal matrix for tangents after fixing the helper. Apply corresponding skinning to tangents/bitangents too: `Base.base_animated_vertex` currently skins its normal but leaves its tangent and bitangent unskinned.

### 7.4 Normal-map orientation differs between families

Single-pass G-buffer vertices negate the bitangent; tiled vertices do not. The eye helper also differs in basis normalization from the world helper. The same sampled green component can therefore tilt a surface in opposite directions between renderers. This cannot explain the black sides of untextured primitives, but it matters for textured aircraft.

Use one documented tangent-basis convention and a diagnostic normal map to verify it. Do not assume a blanket green-channel flip is correct for every imported asset. A sample representing the geometric normal should reproduce the unmapped result; a sample tilted toward positive bitangent should tilt the same way across all renderers.

### 7.5 Color-space handling is mostly present, but CPU colors lack a clear contract

[Material.isSRGBSemantic][material] already loads base-color/emission textures as sRGB and data maps as linear. [Preferences.MainPixelFormat][preferences] is `.bgra8Unorm_srgb`. Deferred resolve textures and the OIT base-color target use that format; [Composition.metal][composition] and [Final.metal][final] simply sample and copy.

An sRGB destination encodes a linear shader output, and sampling that texture decodes it again. An sRGB intermediate followed by an sRGB drawable is therefore not inherently double gamma. The linear tiled albedo attachment and sRGB single-pass albedo attachment are also both valid storage choices if their format conversions are respected. They differ in precision, not in the intended meaning of lighting inputs. Do not add a manual gamma power to these shaders as the first fix. See Apple's [pixel-format documentation](https://developer.apple.com/documentation/metal/mtlpixelformat?language=objc).

However, [RandomColor.randomPaletteColor][random-color] copies platform `CGColor` components without converting their color space. [Material.setBaseColor][material] does the same for `.color` properties. Those components may be nonlinear sRGB, another gamut, or otherwise unsuitable for direct linear-light arithmetic. Monochrome colors also need proper conversion rather than an arbitrary fallback.

For an explicitly sRGB channel of `0.5`, the corresponding linear value is approximately `0.214041`. Treating `0.5` as linear instead displays approximately sRGB `0.735357`. That can make midtone palette colors brighter than expected. It does not explain the renderer-specific absence of illumination.

**Fix:** convert platform color objects through color management to the engine's chosen linear sRGB space before passing components to shaders. Document raw `float3`/`float4` material and scene constants as linear unless their source format explicitly says otherwise. Do not decode an already linear imported numeric value or texture sample again. Saturated red, green, blue, cyan, and magenta are also intentionally present in the palette; colorfulness alone is not proof of a bug.

### 7.6 Tessellated terrain is a separate path

[Tessellation.tessellation_gbuffer_fragment, lines 125–151][terrain] uses a placeholder up normal when no normal texture is bound, copies a normal sample directly otherwise, and does not calculate shadow visibility. Its albedo alpha is still texture alpha even though the tiled light pass interprets it as a shadow factor.

The pictured `FlightboxWithPhysics` ground is a `Quad` created by [GameScene.addGround][game-scene], so this does not explain that ground or the ordinary objects. When testing actual tessellated terrain, define the normal texture's encoding/frame, derive normals from the displaced surface where necessary, transform and normalize them, and explicitly write sun visibility (or one until shadows are supported) into albedo alpha. Do not treat texture opacity as shadowing.

## 8. Repair pseudocode

### 8.1 First establish one diffuse + ambient baseline

**Design decision:** use one sun and the current light controls. Ambient approximates a constant environment contribution and is added once. Set specular to zero during the first comparison. This is a simple engine adaptation, not a physically calibrated material model. The Lambert cosine comes from diffuse reflection; the constant ambient approximation is a deliberate simplification. [PBRT's diffuse-reflection chapter](https://www.pbr-book.org/4ed/Reflection_Models/Diffuse_Reflection) explains the physical diffuse model and its normalization; here its scale is absorbed into the existing artistic light controls.

Do not multiply the proposed ambient by the old `material.ambient`: that field currently mixes legacy ambient reflectance, emission, and the tiled helper's supposed occlusion. The baseline explicitly interprets `light.ambientIntensity` as the effective ambient scale. Proper emission and optional ambient occlusion can be introduced with separate, documented meanings later.

```pseudocode
function shadeDiffuseAndAmbient(baseColorLinear, unitSurfaceNormal,
                                unitDirectionTowardSun, sun, sunlightVisibility)
    // Both directions must be expressed in the same coordinate frame.
    diffuseCosine = max(dot(unitSurfaceNormal, unitDirectionTowardSun), 0)
    sunColorLinear = sun.colorLinear * sun.brightness

    ambientColorLinear = baseColorLinear * sunColorLinear * sun.ambientIntensity
    directDiffuseLinear = baseColorLinear * sunColorLinear * sun.diffuseIntensity
    directDiffuseLinear = directDiffuseLinear * diffuseCosine

    return ambientColorLinear + clamp(sunlightVisibility, 0, 1) * directDiffuseLinear
```

This leaves the renderer architectures intact. No global illumination system, new renderer, or G-buffer material expansion is required for the first diagnosis/repair milestone. For a deliberately unlit surface, output the resolved base color instead; existing sky shaders remain separate. Deferred `material.isLit` is currently not carried through the G-buffer, so full per-material unlit support would need an explicit flag channel or a separate unlit pass. Do not pretend the existing opaque G-buffer already contains it.

**Shadow helper, in [Lighting.metal][lighting-shadow]:** retain cascade selection, out-of-bounds fallback, filtering, and blending. Replace only the final brightness remapping with the clamped filtered visibility. Rename/document the return value so callers cannot confuse it with the old factor.

```pseudocode
function calculateSunlightVisibility(worldPosition_m, viewDepth_m,
                                     worldGeometricNormal, sun, shadowArray)
    if sun has no shadow cascades
        return 1

    // Existing code selects a cascade, compares depths with bias, averages
    // neighboring comparisons, and blends adjacent cascades where needed.
    // Preserve its fully-lit fallback when no supported cascade covers the point.
    filteredVisibility = existingCascadeVisibilityCalculation(...)
    return clamp(filteredVisibility, 0, 1)
```

The helper name above denotes the existing algorithm, not a request to replace the shadow implementation. Audit every `CalculateShadow` caller when changing its contract. Keep the inactive MSAA G-buffer function synchronized if it remains available for future use.

### 8.2 Tiled integration

**Files:** [Lighting.metal][lighting-directional], [TiledDeferredDirectionalLight.metal][tiled-light], [TiledDeferredGBuffer.metal][tiled-gbuffer].

```pseudocode
function writeTiledSurface(surface, scene, sun)
    baseColorLinear = resolveMaterialBaseColor(surface)
    worldNormal = resolveMappedWorldNormal(surface)
    visibility = calculateSunlightVisibility(surface.worldPosition_m,
                                             surface.viewDepth_m,
                                             surface.worldGeometricNormal,
                                             sun, shadowArray)
    gBuffer.albedo = [baseColorLinear.rgb, visibility]
    gBuffer.normal = [worldNormal, 1]
    gBuffer.position = [surface.worldPosition_m, 1]
    return gBuffer

function shadeTiledSurface(gBuffer, sun)
    worldNormal = normalize(gBuffer.normal.xyz)
    colorLinear = shadeDiffuseAndAmbient(gBuffer.albedo.rgb,
                                         worldNormal, sun.direction,
                                         sun, gBuffer.albedo.alpha)
    return [colorLinear, 1]
```

Remove the fabricated `MaterialProperties` values and the subsequent multiplication of the whole result by albedo alpha. Visibility is now applied **inside** the shared equation to direct lighting only. With additional suns in future, add ambient once and sum each sun's direct contribution; the current deferred binding selects only the first sun.

### 8.3 Single-pass integration and normal-space repair

**Files:** [GBuffer.metal][single-gbuffer], [DirectionalLight.metal][single-light], and the shared normal helpers where needed.

```pseudocode
function writeSinglePassSurface(surface, scene, sun)
    baseColorLinear = resolveMaterialBaseColor(surface)
    worldNormal = resolveMappedWorldNormal(surface)

    // Current camera views contain rotation and translation with scale removed.
    // Translation is irrelevant to directions.
    eyeNormal = normalize(scene.worldToEyeRotation * worldNormal)

    visibility = calculateSunlightVisibility(surface.worldPosition_m,
                                             surface.viewDepth_m,
                                             surface.worldGeometricNormal,
                                             sun, shadowArray)
    gBuffer.albedoSpecular = [baseColorLinear.rgb, 0]  // diagnostic matte baseline
    gBuffer.normalShadow = [eyeNormal, visibility]
    gBuffer.depth = surface.viewDepth_m
    return gBuffer

function shadeSinglePassSurface(gBuffer, sun)
    eyeNormal = normalize(gBuffer.normalShadow.xyz)
    colorLinear = shadeDiffuseAndAmbient(gBuffer.albedoSpecular.rgb,
                                         eyeNormal, sun.eyeDirection,
                                         sun, gBuffer.normalShadow.alpha)
    return [colorLinear, 1]
```

Keep the existing separate `worldNormal` available for shadow bias. In the static and animated geometry paths, generate the same world tangent basis as tiled rendering instead of the current contradictory eye-space comments/bitangent negation. If camera scaling is ever allowed, use the view transform's inverse transpose for normals rather than assuming a pure rotation.

Use float precision for the transformed basis and its normalization before producing the stored unit eye normal. In particular, change the `ColorInOut` basis varyings or normalize them in float before any half conversion; do not carry the ground's raw model scale into `half3`. After reading the packed G-buffer normal, renormalize it as shown above because storage quantization can change its length slightly.

### 8.4 OIT integration and transparency

**Files:** [Base.metal][base], [OrderIndependentTransparency.metal][oit-shader], [ShaderHelpers.h][helpers]. Add the same lighting evaluation to the active deferred transparency files.

```pseudocode
function shadeForwardMaterial(surface, material, sun)
    baseColorLinear = resolveMaterialBaseColor(surface)
    opacity = existingOpacityRule(baseColorLinear.alpha, material.opacity)
    if material.isLit
        worldNormal = resolveMappedWorldNormal(surface)
        litColorLinear = shadeDiffuseAndAmbient(baseColorLinear.rgb,
                                                worldNormal, sun.direction,
                                                sun, 1)  // OIT has no cast shadows
    else
        litColorLinear = baseColorLinear.rgb
    return [litColorLinear, opacity]

function storeOITFragment(surface, material, sun)
    straightColor = shadeForwardMaterial(surface, material, sun)
    premultipliedColor.rgb = straightColor.rgb * straightColor.alpha
    premultipliedColor.alpha = straightColor.alpha
    insert premultipliedColor using the existing depth-sorted layer insertion

function blendOITLayers(opaqueColorLinear, layersNearestFirst)
    result = opaqueColorLinear
    for each layer from farthest to nearest
        result = layer.premultipliedRGB + (1 - layer.opacity) * result
    return [result, 1]
```

The opaque OIT shader returns straight lit RGB. Preserve the current opacity policy and sorting while diagnosing lighting. For deferred transparency, output straight lit RGB with the existing source-alpha blend factors; if cast shadows are desired there, calculate visibility with the shared helper. Do not premultiply and then use a blend state that multiplies source RGB by alpha again.

Forward shaders must guard a zero light count before dereferencing sun data. For this baseline, no registered sun means zero sun-derived illumination for lit materials; an explicit scene ambient light independent of the sun can be added later. OIT's existing array/count binding can initially use the first directional light to match deferred behavior.

Also consume `MaterialTextureTransforms` in `Base.material_fragment`: unlike the OIT transparent and deferred material paths, it currently ignores base-color/normal UV transforms. Use the normal map's own UV transform for normal sampling.

### 8.5 Normal-transform repair

**Files:** [Transform.swift][transform], [DrawManager.swift][draw-transforms], and the affected static/animated vertices in [Base.metal][base], [GBuffer.metal][single-gbuffer], [TiledDeferredGBuffer.metal][tiled-gbuffer], and deferred transparency shaders.

```pseudocode
function prepareMeshTransforms(objectWorldTransform, meshLocalTransform)
    combinedTransform = objectWorldTransform * meshLocalTransform
    linearTransform = upperLeft3By3(combinedTransform)
    if linearTransform is singular
        reject or skip this degenerate mesh with a diagnostic
    normalTransform = transpose(inverse(linearTransform))
    return combinedTransform, linearTransform, normalTransform

function makeWorldSurfaceBasis(localNormal, localTangent, localBitangent,
                               linearTransform, normalTransform)
    worldNormal = normalize(normalTransform * localNormal)
    transformedTangent = linearTransform * localTangent
    transformedBitangent = linearTransform * localBitangent
    tangentAlongSurface = transformedTangent
                          - worldNormal * dot(worldNormal, transformedTangent)
    if tangentAlongSurface has negligible length
        return geometric-normal-only basis  // skip normal mapping for this fragment
    worldTangent = normalize(tangentAlongSurface)
    candidateBitangent = cross(worldNormal, worldTangent)
    handedness = sign(dot(candidateBitangent, transformedBitangent))
    if handedness is zero
        return geometric-normal-only basis
    worldBitangent = handedness * candidateBitangent
    return worldNormal, worldTangent, worldBitangent

function resolveMappedWorldNormal(surface)
    normal, tangent, bitangent = makeWorldSurfaceBasis(surface basis and transforms)
    if surface uses object-color override or has no valid normal map or basis
        return normal
    sampleRGB = sample linear normal texture at its transformed UV
    tangentNormal = 2 * sampleRGB - [1, 1, 1]
    if tangentNormal has negligible length
        return normal
    tangentNormal = normalize(tangentNormal)
    return normalize(tangentNormal.x * tangent
                   + tangentNormal.y * bitangent
                   + tangentNormal.z * normal)
```

In practice, transform the basis at the vertex stage and orthogonalize/normalize its interpolated values at the fragment stage. The pseudocode exposes the full calculation for clarity. Skin local position and the full basis consistently first; the existing rigid-joint approximation can remain for this repair, but nonuniformly scaled bones require a separately correct normal transform. Keep normal-matrix construction out of per-fragment work. Preserve the existing once-per-mesh/frame transform cache.

### 8.6 Restore specular only after the baseline agrees

The standard halfway-vector model separates material reflectance, light strength, and highlight exponent. See Microsoft's [specular-lighting equation and halfway-vector definition](https://learn.microsoft.com/en-us/windows/uwp/graphics-concepts/specular-lighting).

```pseudocode
function calculateDirectSpecular(unitNormal, unitTowardLight, unitTowardCamera,
                                 materialSpecularColorLinear, materialExponent,
                                 lightColorLinear, lightSpecularStrength)
    if dot(unitNormal, unitTowardLight) <= 0
        return [0, 0, 0]
    if dot(unitNormal, unitTowardCamera) <= 0 or lightSpecularStrength <= 0
        return [0, 0, 0]
    halfwaySum = unitTowardLight + unitTowardCamera
    if halfwaySum has negligible length
        return [0, 0, 0]
    unitHalfwayDirection = normalize(halfwaySum)
    highlightCosine = max(dot(unitNormal, unitHalfwayDirection), 0)
    highlight = highlightCosine ^ max(materialExponent, 1)
    return materialSpecularColorLinear * lightColorLinear
           * lightSpecularStrength * highlight

finalColorLinear = ambientColorLinear
                 + sunlightVisibility * (directDiffuseLinear + directSpecularLinear)
```

Do not silently reuse `shininess` as metalness, `specularIntensity` as an exponent, or a shadow channel as specular strength. Use a matte diagnostic material with zero specular first; optional exponent `32` in the worked example is an illustrative tuning choice, not a measured aircraft-material value.

Single-pass currently stores only one specular scalar and tiled currently stores neither an exponent nor specular color. Full per-material specular parity therefore requires a **documented G-buffer layout extension**, with [TFSCommon.h][common], [ShaderDefinitions.h][definitions], both G-buffer texture definitions, and all consuming pipeline formats updated together. Alternatively, use the same explicit global specular settings in all families as a limited intermediate experiment. Do not pretend the current layouts can recover material parameters that were discarded.

Revisit [MetalTypes.swift][metal-types] and [Material.swift][material] so omitted specular properties have an intentional default and explicit zero values survive import. Their current nonzero-only assignment logic makes a deliberate zero difficult to preserve.

### 8.7 CPU color conversion and optional high dynamic range

```pseudocode
function importPlatformColor(platformColor)
    convertedColor = colorManage(platformColor, destination = linearSRGB)
    return [convertedColor.red, convertedColor.green,
            convertedColor.blue, convertedColor.alpha]

function importNumericMaterialColor(value, declaredSourceEncoding)
    if declaredSourceEncoding is linearRGB
        return value
    if declaredSourceEncoding is sRGB
        return [decodeSRGB(value.rgb), value.alpha]
    return colorManage(value, declaredSourceEncoding, linearSRGB)
```

Keep the current sRGB drawable. If bright specular or multiple lights should retain values above one, a later high dynamic range (HDR) milestone can use linear floating-point lighting targets and tone map once at presentation. This requires changing **both allocation and every matching pipeline attachment**, not only `Preferences.MainPixelFormat`.

Affected sites include [LateDrawablePresenting.swift][late-present], the three deferred pipeline files, [OITRenderer.swift][oit-renderer], [OrderIndependentTransparencyPipeline.swift][pipeline-oit], and the final/composite shaders. OIT's `rgba8unorm` layer store also clips each stored fragment; an HDR OIT version needs a suitable floating-point layer store and a rechecked image-block memory budget. Adding tone mapping after an 8-bit store cannot recover values already clipped. HDR is optional follow-up work; it does not repair missing ambient light, space mismatches, or disabled lighting.

## 9. Files to change, grouped by purpose

Paths below are under `ToyFlightSimulator Shared/`. Links lead to the inspected source locations.

| Purpose | Files |
|---|---|
| Shared diffuse/ambient equation and sun-visibility contract | [Graphics/Shaders/Lighting.metal][lighting-directional] |
| Fix all three tiled opaque paths | [Graphics/Shaders/TiledDeferredDirectionalLight.metal][tiled-light], [Graphics/Shaders/TiledDeferredGBuffer.metal][tiled-gbuffer] |
| Fix single-pass normal space, fallback color, diffuse floor, specular, and shadow application | [Graphics/Shaders/GBuffer.metal][single-gbuffer], [Graphics/Shaders/DirectionalLight.metal][single-light] |
| Enable OIT shading and fix UV/basis/fallback inconsistencies | [Graphics/Shaders/Base.metal][base], [Graphics/Shaders/OrderIndependentTransparency.metal][oit-shader], [Graphics/Shaders/ShaderHelpers.h][helpers] |
| Shade deferred transparent materials | [Graphics/Shaders/TiledDeferredTransparency.metal][transparent-tiled], [Graphics/Shaders/SinglePassDeferredTransparency.metal][transparent-single] |
| Correct tiled animated transparency dispatch | [Graphics/Libraries/Pipelines/Render/RenderPipelineStateLibrary.swift][animated-variants], [TiledDeferredPipeline.swift][pipeline-tiled], [TiledMSAAPipeline.swift][pipeline-msaa]; register a new shader only if an existing compatible skinned vertex entry point cannot be reused |
| Correct general normal transforms and nil-material binding | [Math/Transform.swift][transform], [Managers/DrawManager.swift][draw-transforms], the vertex shader sites listed in §8.5 |
| Define material/color import semantics and defaults | [AssetPipeline/Material.swift][material], [Utils/RandomColor.swift][random-color], [Core/Types/MetalTypes.swift][metal-types]; audit [Colors.swift][colors] constants for their intended encoding |
| Separate point-light follow-up | [Graphics/Shaders/PointLights.metal][point-lights], [Lighting.CalculatePointLighting][lighting-point], [TiledDeferredPointLight.metal][tiled-point] |
| Actual tessellated-terrain follow-up | [Graphics/Shaders/Tessellation.metal][terrain] and its normal/height-map producer |
| Optional material-layout / HDR follow-up | [Graphics/Shaders/TFSCommon.h][common], [ShaderDefinitions.h][definitions], [SinglePassDeferredGBufferTextures.swift][textures-single], [TiledDeferredGBufferTextures.swift][textures-tiled], relevant pipeline files, [LateDrawablePresenting.swift][late-present], OIT layer storage, [Composition.metal][composition], [Final.metal][final] |

`FlightboxWithPhysics.swift` does not need a larger ambient setting to repair these defects. Its existing `0.4`/`0.5` settings provide a useful initial baseline. The three tiled renderer classes do not each need a separate lighting algorithm.

## 10. Verification sequence and expected results

### Milestone 1 — diffuse/ambient parity

Learning objective: distinguish surface color, direct illumination, ambient illumination, and visibility.

Prerequisites: fixed material colors, fixed camera/light, no specular, and a deterministic scene. Use a cube, a sphere, a slanted plane, and the aircraft. Preserve identical inputs across renderer rebuilds instead of comparing newly randomized scenes.

For a linear gray albedo of `0.5`, white light, brightness `1`, ambient `0.4`, and diffuse `0.5`, scratch calculations gave:

| Diffuse cosine | Visibility | Existing tiled linear RGB per channel | Proposed linear RGB per channel |
|---:|---:|---:|---:|
| 0 | 1 | 0 | 0.200 |
| 0.5 | 1 | 0.225 | 0.325 |
| 1 | 1 | 0.450 | 0.450 |
| 1 | 0 | 0.225, due to old shadow remapping | 0.200, ambient only |

The proposed fully lit top remains at `0.45`, while the side gains ambient visibility. These values are **linear shader values**, not screenshot byte values. Approximate sRGB encodings for `0.2`, `0.325`, and `0.45` are `0.484529`, `0.605497`, and `0.701411`.

Completion checks:

- Matte surfaces agree between renderer families away from edges; expect small storage/quantization differences, not byte-identical output.
- Turning ambient to zero restores black back-facing sides; turning it up changes them smoothly.
- Turning diffuse intensity to zero leaves ambient only.
- Turning brightness to zero removes this sun's ambient and direct terms.
- Blocking the sun removes direct light but preserves ambient. OIT remains unshadowed by design.
- Use a GPU capture or app-owned readback target if comparing numeric shader outputs. Screenshot profiles and compositor conversions can alter stored screenshot RGB.

### Milestone 2 — space, material, and normal-map correctness

Learning objective: preserve physical directions and source colors through every transform/pass.

- Rotate only the camera with specular disabled. A fixed surface's diffuse brightness must not change. Reproduce the §5.1 world/eye example with pure vector arithmetic.
- Test an untextured, non-overridden material with a color deliberately different from its vertex color. Material paths should agree on the documented fallback.
- Test an explicitly vertex-colored mesh through its designated path.
- Test a materialless submesh after a textured one; it must not inherit that texture.
- Test a normal map representing the geometric normal and then one tilted toward positive bitangent. Every renderer must agree on the tilt.
- Scale a slanted surface unequally and check that the transformed normal remains perpendicular to both transformed tangents.
- Render the million-scale ground and inspect the single-pass normal for finite, unit-length values. Scratch checks confirmed that `1,000,000` exceeds finite binary16 range, whereas unit components are representable; a scalar squared length of `0.000001²` rounds to zero in binary16. Do the transform/normalization in float before narrowing.
- Move an animated control surface; its shading must follow its new orientation.
- In single-pass G-buffer debug views, distinguish world and eye normals and check the expected view rotation explicitly.

Pure vector/color calculations can be checked without Metal. Material import, actual attachments, shader execution, and animation need app/GPU validation. Updating `Transform.normalMatrix` also requires revisiting the existing expectations in `ToyFlightSimulatorTests/Math/TransformTests.swift` rather than preserving a test that asserts the old shortcut.

### Milestone 3 — transparent materials and specular

Learning objective: keep lighting separate from compositing and keep specular width separate from strength.

- A lit transparent sphere should retain a brightness gradient. For straight lit color `0.6`, opacity `0.5`, and background `0.2`, the expected composed channel is `0.4`. Premultiplying twice would fail this check.
- Check static and skinned transparent submeshes in every renderer, including both tiled sample counts. Confirm the selected fragment shader writes blended lighting, not G-buffer data.
- Restore specular with the corrected equation. Zero strength must eliminate it; changing the exponent should change highlight width without replacing the strength control.
- View highlights in a floating-point diagnostic target if checking whether they exceed one. An 8-bit target has already lost that information.
- The existing OIT four-layer limit and conventional deferred transparency ordering can still produce overlap differences. They are separate from the lighting fix.

### Point lights and terrain: targeted follow-ups

The inspected `FlightboxWithPhysics.buildScene()` registers a sun and no point lights. Point lights are therefore not the primary explanation for these images. Nevertheless, [PointLights.metal, lines 95–107][point-lights] uses `normal_shadow.w` as specular strength even though that channel contains sun shadowing, and forms its halfway vector from unnormalized distance-bearing vectors. Correct it to use the actual material specular field and `normalize(unitTowardLight + unitTowardCamera)`. Keep point-light contributions independent of sun visibility. The tiled point-light helper also ignores brightness/diffuse intensity; bring those controls into agreement when validating point-light scenes.

Actual tessellated terrain should be tested in a terrain scene after ordinary mesh lighting agrees. Validate its normal producer and explicit visibility channel separately. Neither fixing terrain nor adjusting shadow bias substitutes for the primary repairs.

## 11. References and design attribution

The diagnosis comes from this checkout; the proposed shared equation and repair order are Codex's design for this engine. The baseline deliberately omits metalness, physically calibrated light units, image-based lighting, and full material BRDF transport. Those would change material fidelity and are not required to resolve the current mismatch.

1. **Diffuse reflection explanation and reference implementation:** [Pharr, Jakob, and Humphreys, PBRT 4th edition, §9.2](https://www.pbr-book.org/4ed/Reflection_Models/Diffuse_Reflection). Read `DiffuseBxDF::f` and the discussion of the cosine term. Directly fetched. Provides the physical reference; this document adapts it to existing artistic intensity controls.
2. **Specular explanation:** [Microsoft, Specular lighting](https://learn.microsoft.com/en-us/windows/uwp/graphics-concepts/specular-lighting). Directly fetched. The equation separates material specular color, light color/strength, and exponent; the halfway vector uses normalized light/view directions.
3. **Original historical reference:** James F. Blinn, *Models of Light Reflection for Computer Synthesized Pictures*, SIGGRAPH 1977, pp. 192–198, listed on [Blinn's own publications page](https://www.jimblinn.com/publications/). The author/title/venue were verified there; the original paper itself was not retrieved. The operational formula above is checked against Microsoft's explanation.
4. **Metal format semantics:** [Apple, MTLPixelFormat](https://developer.apple.com/documentation/metal/mtlpixelformat?language=objc). Official indexed documentation confirms sRGB conversion on reads/writes and linear alpha. The full page required JavaScript in the text fetch, so no claim is made that a full specification was reviewed.
5. **Deferred renderer reference implementation:** [Apple, Rendering a scene with deferred lighting in Swift](https://developer.apple.com/documentation/Metal/rendering-a-scene-with-deferred-lighting-in-swift). Official indexed article inspected. Study the G-buffer generation and directional-light stages, especially the contract between stored normals and lighting vectors. Its renderer organization is a reference, not a reason to copy unrelated artistic constants.
6. **OIT reference implementation:** [Apple, Implementing order-independent transparency with image blocks](https://developer.apple.com/documentation/metal/implementing-order-independent-transparency-with-image-blocks?changes=_10&language=objc). Official indexed article inspected. Study `TransparentFragmentValues` and `processTransparentFragments` for layer insertion/composition. Surface illumination is a separate calculation to perform before storing each fragment.

The existing tiled/MSAA selection already provides the architecture comparison. First make all paths evaluate the same surface model. Later optimization should preserve that model and be measured with identical scenes; adding physically based specular, environment lighting, or tone mapping is a fidelity/design change rather than a pure optimization.

[shot-tiled]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/debugging/screenshots/TiledDeferredColors.png>
[shot-single]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/debugging/screenshots/SinglePassDeferredColors.png>
[shot-oit]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/debugging/screenshots/OIT_Colors.png>
[scene]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift:171>
[game-scene]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Scenes/GameScene.swift:119>
[gameobject]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/GameObjects/GameObject.swift:80>
[lights]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Managers/LightManager.swift:54>
[draw-material]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Managers/DrawManager.swift:569>
[draw-transforms]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Managers/DrawManager.swift:525>
[transform]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Math/Transform.swift:64>
[material]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/AssetPipeline/Material.swift:86>
[metal-types]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Core/Types/MetalTypes.swift:71>
[random-color]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Utils/RandomColor.swift:46>
[colors]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Colors.swift:10>
[preferences]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Core/Preferences.swift:25>
[oit-renderer]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Display/OITRenderer.swift:84>
[late-present]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Display/Protocols/LateDrawablePresenting.swift:28>
[lighting-phong]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/Lighting.metal:18>
[lighting-directional]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/Lighting.metal:62>
[lighting-shadow]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/Lighting.metal:159>
[lighting-point]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/Lighting.metal:213>
[tiled-light]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredDirectionalLight.metal:15>
[tiled-gbuffer]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredGBuffer.metal:76>
[single-gbuffer]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/GBuffer.metal:45>
[single-light]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/DirectionalLight.metal:41>
[base]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/Base.metal:98>
[oit-shader]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/OrderIndependentTransparency.metal:67>
[helpers]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/ShaderHelpers.h:31>
[common]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/TFSCommon.h:42>
[definitions]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/ShaderDefinitions.h:56>
[transparent-tiled]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredTransparency.metal:38>
[transparent-single]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/SinglePassDeferredTransparency.metal:72>
[point-lights]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/PointLights.metal:80>
[tiled-point]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/TiledDeferredPointLight.metal:43>
[terrain]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/Tessellation.metal:125>
[composition]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/Composition.metal:21>
[final]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Shaders/Final.metal:14>
[pipeline-tiled]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Libraries/Pipelines/Render/TiledDeferredPipeline.swift:8>
[pipeline-msaa]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Libraries/Pipelines/Render/TiledMSAAPipeline.swift:46>
[pipeline-single]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Libraries/Pipelines/Render/SinglePassDeferredPipeline.swift:46>
[pipeline-oit]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Libraries/Pipelines/Render/OrderIndependentTransparencyPipeline.swift:58>
[animated-variants]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Libraries/Pipelines/Render/RenderPipelineStateLibrary.swift:68>
[textures-single]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Libraries/GBuffers/SinglePassDeferredGBufferTextures.swift:17>
[textures-tiled]: </Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/Graphics/Libraries/GBuffers/TiledDeferredGBufferTextures.swift:18>
