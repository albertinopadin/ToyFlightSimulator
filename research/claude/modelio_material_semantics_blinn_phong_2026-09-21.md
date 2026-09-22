# Model I/O Material Semantics for the Blinn-Phong Material — Research

**Date:** 2026-09-21 · **Agent:** claude
**Question:** Which `MDLMaterialSemantic` values should feed the engine's `MaterialProperties` (albedo
fallback, specular strength, shininess, opacity, and a future emission term) for the repo's OBJ/MTL and
USDZ assets, what the `.emission` slot really holds, and whether `Material` should mirror the enum.
**Method:** Every mapping claim was measured on this machine (macOS 27, Xcode 26 SDK) with
`scripts/inspect_mdl_materials.swift`: a synthetic MTL carrying every standard key, then all 13 OBJ/USD
models under `ToyFlightSimulator Shared/Core/Resources/Models`. The Model I/O header `MDLMaterial.h` was
read from the SDK. The three.js `MTLLoader.js` source, the UsdPreviewSurface specification, Karis's
"Specular BRDF Reference" and the Wavefront MTL specification were fetched and quoted. Apple's
deferred-lighting sample and the Kodeco chapter are cited from prior knowledge of their code (page titles
and a search excerpt checked; code not re-fetched). Every number comes from
`scripts/blinn_phong_roughness_table.swift` or the inspection script.

## Executive summary

1. **For OBJ files, Model I/O stores the MTL `Ka` line (ambient reflectivity) under `.emission` and drops
   `Ke` entirely.** The synthetic probe with `Ka 0.11 0.12 0.13` and `Ke 0.41 0.42 0.43` produced emission
   (0.11, 0.12, 0.13); `Ke` alone produced the black default. Blender writes `Ka 1 1 1` unconditionally,
   which is what the F-16, sphere and quad carry, so "emission" on those files is full white. [verified]
2. **`.specular` and `.specularExponent` are the right semantics for the Blinn-Phong strength and
   exponent: they are the MTL `Ks` and `Ns` lines.** Accept `.specular` only when its type is `.float3`
   (or a texture): USD materials arrive with a scalar float 0 placeholder, and no USD material in the repo
   has a `.specularExponent` at all. [verified]
3. **USD assets carry `.roughness` instead of an exponent; derive shininess with Karis's Blinn-Phong ↔
   Beckmann approximation, α = roughness², exponent = 2/α² − 2.** Apple's header states this derivation is
   intended. Roughness 0.5 gives 30; the engine default 32 corresponds to roughness 0.49, essentially the
   UsdPreviewSurface default of 0.5. [fetched; the header statement verified in the SDK]
4. **Emission is light the surface gives off by itself, added after lighting and untouched by N·L, the
   shadow lit fraction or the sun color.** Only the USD dialect supplies a usable value: the Sketchfab
   F-22's landing lights author `emissiveColor` white, and the RealityConverter F-18 and cgtrader F-35
   emissive textures measure essentially black. The engine has no shader term for it yet; until it does,
   stop mapping `.emission` into `ambient`, which the new lighting never reads. [verified]
5. **`Material` should not mirror `MDLMaterialSemantic`.** The enum is a union of two dialects, the
   Phong-era MTL keys and the Disney-style UsdPreviewSurface inputs. The engine struct should hold exactly
   the Blinn-Phong parameters the shaders consume, with one small translation table per dialect. This is
   how Apple's sample, three.js and Kodeco's book do it. [fetched for three.js; unverified for the others]
6. **Defect: `Material.populateMaterial` lets the last `.baseColor` value win, and Model I/O lists its own
   0.18 gray default after the authored USD `diffuseColor`, so every untextured USD material renders
   gray.** The Sketchfab F-22 canopy authors (1.0, 0.44, 0.07) at opacity 0.6, the HUD glass
   (0.01, 0.29, 0.0) and the landing lights 0.8; all three end at (0.18, 0.18, 0.18). First-wins fixes it
   (§2.2). [verified]
7. **Step 6 of the shading-mismatch fix has landed with three gaps** (Appendix B): the single-pass sun pass
   still passes the zero strength and exponent 1, the tiled sun pass reads whatever material the last
   opaque submesh left bound, and the new `.roughness` import case is dead code with the wrong target
   field and the wrong formula. [verified against the working tree]

## Terms

- **MTL** — the Wavefront material file next to an `.obj`. Each `newmtl` block lists Phong-era keys:
  `Ka` ambient reflectivity, `Kd` diffuse reflectivity (the surface color), `Ks` specular reflectivity
  (highlight color and strength), `Ns` specular exponent (highlight tightness, 0 to 1000), `d` dissolve
  (1 opaque), `Tr` transparency (an exporter convention, `1 − d` or `d`), `Ke` emissive color (a common
  extension), `illum` illumination model, `map_*` the texture for a key.
- **UsdPreviewSurface** — the standard USD shading node. Inputs: `diffuseColor`, `emissiveColor`,
  `useSpecularWorkflow`, `specularColor`, `metallic`, `roughness`, `clearcoat`, `clearcoatRoughness`,
  `opacity`, `ior`, `normal`, `occlusion`, `displacement`.
- **Semantic** — `MDLMaterialSemantic`, the meaning tag Model I/O attaches to each `MDLMaterialProperty`
  so a renderer can ask "give me the base color" without knowing the file format.
- **Scattering function** — `MDLScatteringFunction` (Lambert + Blinn-Phong) or
  `MDLPhysicallyPlausibleScatteringFunction` (Disney-style PBR), the object that owns a material's default
  property objects. Model I/O creates one per material.
- **Dialect** — used here for the two source vocabularies, MTL and UsdPreviewSurface, that the one enum
  has to represent.
- **Albedo** — the surface's own color before lighting. **Strength** — the scalar that multiplies the
  Blinn-Phong highlight. **Exponent** (shininess) — the power the half-vector cosine is raised to.
  **Roughness** — the PBR microfacet parameter, 0 mirror to 1 matte; **α** — roughness², the
  Beckmann/GGX lobe width.
- **Lit fraction** — the 0..1 shadow visibility the engine's shared shading function multiplies into the
  direct terms.

## Part 1 — The problem and the ideas

### 1.1 The problem

The engine shades every renderer with one Blinn-Phong function (`Lighting::ShadeDirectionalBlinnPhong`,
landed in the shading-mismatch fix):

    color    = ambient + litFraction × (diffuse + specular)
    ambient  = albedo × lightColor × brightness × ambientIntensity
    diffuse  = albedo × lightColor × brightness × diffuseIntensity × max(N·L, 0)
    specular = lightColor × brightness × specularIntensity × strength × pow(max(N·H, 0), exponent)

It needs four material inputs per submesh: albedo (a texture or a constant), strength, exponent and
opacity. Model I/O hands the importer an `MDLMaterial`, a flat list of properties tagged with semantics,
and the same enum has to describe an MTL file from 1995 and a UsdPreviewSurface from 2019. The naive
importer, "loop over every semantic and copy whatever has the same name", goes wrong in four ways the
probe made visible:

1. The OBJ importer reuses the `.emission` slot for `Ka`.
2. Model I/O pads every material with PBR defaults that are not in the file (roughness 0.9, `ao` 0.0,
   sheen 0.05 on every OBJ material), and lists its own defaults after the authored USD inputs, so a loop
   that keeps the last value keeps the default.
3. The two dialects express the highlight differently: MTL gives `Ks` + `Ns`, USD gives `roughness`
   (+ `metallic`) and a scalar `specular` placeholder of 0.
4. Some MTL keys are simply dropped (`Ke`, `Tr`, `illum`), so their absence has to be handled, not their
   value.

### 1.2 The core idea

**Idea A — translate each dialect into the shading model's parameters.**

**Intuition.** The importer's job is not to preserve the file's vocabulary but to answer the shader's
four questions. Each dialect gets a small, explicit table; the engine struct stays the shading model's
parameter list.

**The steps.**
1. Decide the dialect from the file extension (`ObjModel` and `UsdModel` already know it).
2. For each semantic the shader needs, take the FIRST property with that semantic
   (`MDLMaterial.property(with:)`). In `properties(with:)` order Model I/O lists authored USD inputs
   first and its defaults after; OBJ materials have one property per semantic because `Kd` and `map_Kd`
   are merged into one.
3. Accept a value only when its type is the authored type for that dialect (`.float3` for `Ks`, `.float`
   for `Ns` and `d`, a texture for maps). A scalar `.specular`, a 0.9 roughness on an OBJ material, or a
   0.0 `ao` are Model I/O placeholders and keep the engine default.
4. Fill what the dialect lacks from the other parameterization: the USD exponent from roughness (Idea C),
   an MTL matte from `Ns < 1`.
5. Ignore what the dialect cannot express: MTL `.emission` (it is `Ka`), the USD `.specular` scalar.

```pseudocode
function importMaterial(mdlMaterial, dialect) -> engineMaterial      // dialect: wavefrontMTL | usdPreviewSurface
    engineMaterial = defaults()                                       // baseColor debug pink, specularStrength 0.25, shininess 32, opacity 1

    baseColorProperty = firstProperty(mdlMaterial, baseColor)         // USD "diffuseColor"; OBJ Kd or map_Kd (one merged property)
    if baseColorProperty is texture:        engineMaterial.baseColorTexture = load(baseColorProperty, sRGB: true)
    else if baseColorProperty is float3 / float4 / color:
                                            engineMaterial.baseColor = value(baseColorProperty)

    specularProperty = firstProperty(mdlMaterial, specular)
    if specularProperty is texture:         engineMaterial.specularTexture = load(specularProperty, sRGB: false)
    else if specularProperty is float3:     engineMaterial.specularStrength = specularProperty.float3.r   // authored Ks; a scalar float is the USD placeholder

    exponentProperty = firstProperty(mdlMaterial, specularExponent)   // MTL Ns; absent for USD
    if exponentProperty exists and is float:
        if exponentProperty.float < 1:      engineMaterial.specularStrength = 0                          // Ns 0 means "no highlight"
        else:                               engineMaterial.shininess = exponentProperty.float
    else if dialect == usdPreviewSurface:
        roughnessProperty = firstProperty(mdlMaterial, roughness)
        if roughnessProperty is float:      engineMaterial.shininess = exponentFromRoughness(roughnessProperty.float)   // Idea C

    if dialect == usdPreviewSurface:
        emissionProperty = firstProperty(mdlMaterial, emission)       // "emissiveColor"; Model I/O's default is listed second
        if emissionProperty is texture:     engineMaterial.emissionTexture = load(emissionProperty, sRGB: true)
        else if emissionProperty is float3: engineMaterial.emission = emissionProperty.float3
    // wavefrontMTL: semantic emission holds Ka; the lighting model has no per-material ambient term, so ignore it

    opacityProperty = firstProperty(mdlMaterial, opacity)             // MTL d, USD opacity; Tr is dropped by Model I/O
    if opacityProperty is float:            engineMaterial.opacity = opacityProperty.float
    return engineMaterial
```

**Assumptions and limits.** The authored-first ordering was observed on this SDK on five USD files through
`properties(with:)`; the header only promises that `property(with:)` returns "the first occurrence", and
by-index enumeration (`material[i]`) lists the defaults first, so a loop over indices would behave
differently. A material with `Kd` and `map_Kd` keeps the `Kd` value inside the texture-typed property's
`float3Value`, which is harmless because `ResolveBaseColor` prefers the texture. Texture-typed roughness
and metallic maps are loaded into `roughnessTexture` / `metallicTexture` but no shader samples them yet.

**Idea B — emission as an additive term.**

**The math.** With the engine's function,

    color = emission + ambient + litFraction × (diffuse + specular)

where `emission` is a linear RGB radiance in the same units as `albedo × lightColor × brightness`. A
value of 1.0 is as bright as a fully lit white surface. It is added once per pixel, not once per light.

**Where it would live.** The forward paths (OIT, the two transparency fragments) add it in the fragment.
The tiled G-buffer has a `lighting` target that the geometry pass could initialize with the emission
before the light passes accumulate into it. The single-pass G-buffer (albedo+specular, normal+shadow,
depth) has no spare channel, so it needs a layout change or a separate additive pass. That is a plan, not
this document.

**Edge cases.** An unlit material (`isLit == false`) already shows its base color; emission on top of that
would double-count for a self-lit object, so define unlit as "base color only" and keep emission for lit
materials. Emissive textures load sRGB (they are colors), which `Material.isSRGBSemantic` already does for
`.emission`.

**Idea C — exponent from roughness.**

**The math.** Karis (2013) writes the Blinn-Phong normal distribution as
D = 1 / (π α²) · (n·h)^(2/α² − 2) with α = roughness², so a Blinn-Phong exponent that matches a Beckmann
lobe of width α is

    exponent = 2 / α² − 2 = 2 / roughness⁴ − 2

and the inverse, useful for reading an MTL `Ns` as a roughness, is `roughness = (2 / (exponent + 2))^(1/4)`.

**Worked example** (reproduced by `scripts/blinn_phong_roughness_table.swift`):

| roughness | exponent | | `Ns` | roughness |
|---|---|---|---|---|
| 0.1 | 19 998 | | 10 (Temple) | 0.64 |
| 0.3 | 245 | | 16 (F-16) | 0.58 |
| 0.5 | 30 | | 32 (engine default) | 0.49 |
| 0.7 | 6.3 | | 80 (F-18) | 0.40 |
| 0.9 | 1.0 | | 225 (sphere) | 0.31 |
| 1.0 | 0 | | | |

**Assumptions and limits.** Roughness 0 gives infinity and roughness 1 gives 0; clamp the result to
[1, 1024]. The conversion matches lobe width, not energy: the engine's Blinn-Phong is unnormalized (no
(n + 2) / 8π factor), so a converted exponent changes only the highlight's size, and the strength still
comes from `Ks` or the default. A metallic-workflow USD material has no specular color; the dielectric
reflectance F0 = 0.04 that PBR uses is far below the 0.25 default, which was chosen for this unnormalized
lobe. Treat the default as the strength for USD until a normalized or PBR path exists.

**What `Ks` and `Ns` do to the picture.** The half-width of the highlight, the angle between N and H
where `pow(N·H, Ns)` has fallen to one half:

| `Ns` | 1 | 2 | 16 | 32 | 80 | 225 |
|---|---|---|---|---|---|---|
| half-width | 60° | 45° | 16.7° | 11.9° | 7.5° | 4.5° |

At N·H = 0.95 (18° off the highlight center) an exponent of 16 with strength 1.0 adds 0.44 of the sun's
radiance in white; with strength 0.25 it adds 0.11. Both the F-16 and the F-18 carry `Ks 1 1 1`, which
looks like an exporter default rather than a deliberate choice (Blender writes its Specular slider; the
Blender-exported sphere has 0.5), so importing it faithfully will make the F-16 look like glossy plastic.
That is a fact about the asset, not a bug in the importer.

### 1.3 How existing engines and simulators do it

- **Apple, "Rendering a scene with deferred lighting" (Metal sample)** — the Temple in this repo
  (`Temple.mtl` with `StructureBaseColorMap`, `StructureSpecularMap`, `StructureNormalMap`) is that
  sample's asset. Its mesh loader creates three textures per submesh from `MDLMaterialSemanticBaseColor`,
  `MDLMaterialSemanticSpecular` and `MDLMaterialSemanticTangentSpaceNormal` and reads no other semantic;
  the engine's `TFSTextureIndexBaseColor/Specular/Normal` mirror it. Study: the mesh file (`AAPLMesh`),
  the submesh initializer's texture creation. [unverified: from prior knowledge of the sample code; the
  Temple asset match is verified locally]
- **three.js `MTLLoader`** — `createMaterial_` maps `kd` → color, `ks` → specular, `ke` → emissive,
  `ns` → shininess, `d` → opacity, `tr` → `1 − value` (with an `invertTrProperty` option),
  `map_kd/ks/ke/d`, `norm`, `map_bump`/`bump`, `disp`. `ka` is parsed but never applied. Study: the
  `switch (prop)` in `createMaterial_`. [fetched]
- **Kodeco, Metal by Tutorials, "Maps & Materials"** — a small `Material` struct (base color, specular
  color, shininess, plus roughness / metallic / ambient occlusion in later editions) filled with
  `material?.property(with: .specularExponent)` and a `.float` type check, the same pattern for the other
  semantics. Study: the material extension in the chapter's project. [fetched: the chapter search excerpt
  confirms the `.specularExponent` pattern; the field list is from memory]
- **SceneKit's Model I/O bridge (this repo)** — `AircraftThumbnailGenerator.sanitizeObjMaterials` resets
  `emission` to black and `transparent` to opaque after `SCNScene(mdlAsset:)` because OBJ materials
  arrived glowing white. The root cause is the same `Ka` → emission mapping measured here. [verified]
- **Model I/O itself** — the header says the base `MDLScatteringFunction` "is Lambertian, with a
  Blinn-Phong specular response. Specular power for Blinn-Phong can be derived from the roughness property
  using an approximation." `propertyWithSemantic:` "Returns the first occurence of the property that
  matches the semantic. Not recommended to use when there are multiple properties with same semantic."
  `propertiesWithSemantic:` "Returns the complete list of properties that match the semantic (e.g. Kd &
  Kd_map)". Also: "If a color is encoded in a floatN property, it is to be interpreted as a Rec 709
  color." [verified, SDK header]

### 1.4 Tradeoffs

| Approach | Correctness | Complexity to implement | Runtime cost | What it teaches | Origin |
|---|---|---|---|---|---|
| Mirror `MDLMaterialSemantic` in `MaterialProperties` | Low: the shader still reads four fields, the rest is dead weight, and `.emission` would carry `Ka` for OBJ | Medium (26 fields, buffer layout) | Larger per-submesh upload | Little | agent's own strawman |
| Blinn-Phong struct + one translation table per dialect (recommended) | High for what the shader does; matte MTL and USD roughness handled | Low: a few type checks and first-wins | None | The difference between file vocabulary and shading parameters | three.js MTLLoader, Kodeco, Apple sample; adapted to this codebase |
| Metallic-roughness PBR (Cook-Torrance GGX), Blinn-Phong kept as reference | Highest for USD; MTL needs the inverse conversion | High: new shading function, sampled roughness / metallic / AO maps, G-buffer channels | Higher per pixel | Microfacet theory, energy conservation | Burley 2012, Karis 2013 |

### 1.5 Evidence quality

- Documented facts: the MTL key meanings and the `Ns` range (MTL spec); the UsdPreviewSurface inputs,
  defaults and the two workflows (spec); the Model I/O API contracts (SDK header).
- Measured on this machine: every mapping in Appendix A, the property order, the emissive texture
  statistics. Model I/O's importer behavior is not documented; a future SDK could change the `Ka` handling
  or the ordering. The script re-checks it in a minute.
- General principles: the Blinn-Phong formula and Karis's conversion.
- Not applicable: no aircraft behavior is involved.

### 1.6 What did not survive verification

- "`Ke` maps to `.emission`" — false on this SDK; `Ke` and `map_Ke` are dropped and `Ka` / `map_Ka` take
  the slot.
- "`Tr` sets the opacity" — false; only `d` does. The F-18's `Tr 1.000000` produces no opacity property,
  so its Glass material imports opaque.
- "`Material.populateMaterial` fixed the F-22 canopy and HUD glass" (the asset-pipeline rule's note) —
  half true: handling `.float3` stopped the debug pink, but last-wins now paints them 0.18 gray.
- "Model I/O's `.emission` ≈ ambient, so mapping it into `ambient` is harmless" — it was harmless only
  because the new lighting ignores `ambient`; as an emission source it is wrong for OBJ.
- Not covered: glTF (Model I/O does not import it), the sRGB-vs-linear question for `.color`-typed
  properties (a follow-up in the shading doc), point-light materials, a normalized Blinn-Phong.

## Part 2 — Applying it to ToyFlightSimulator

### 2.1 Where the engine is today

- `ToyFlightSimulator Shared/AssetPipeline/Material.swift` — `init` calls `setProperties` (reads
  `.emission → ambient`, `.baseColor → diffuse`, `.specular`, `.specularExponent`, `.opacity` through
  `property(with:)`, first occurrence) and then `populateMaterial`, which loops over every semantic and
  every property: textures into the texture slots, `.color/.float3/.float4` `.baseColor` values into
  `properties.color` with the last one winning (the `case .color, .float3, .float4:` branch;
  `setBaseColor` below it). A `.roughness` case was added to `setProperties` in the Step 6 working tree;
  see Appendix B.
- `ToyFlightSimulator Shared/Core/Types/MetalTypes.swift` and `Graphics/Shaders/TFSCommon.h` —
  `MaterialProperties { color, ambient, diffuse, specular, shininess, opacity, isLit }`, defaults now
  (0.25, 0.25, 0.25) and 32 (Step 6).
- What the shaders read: `material.color` as the untextured albedo fallback (`ResolveBaseColor`),
  `material.specular.r` as the strength (G-buffer `albedo_specular.w`, the four forward fragments, the
  tiled sun fragment), `material.shininess`, `material.opacity`, `material.isLit`. `ambient` and
  `diffuse` are read only by the deprecated `Lighting::GetPhongIntensity` and the unbound
  `og_tiled_deferred_directional_light_fragment`.
- Texture slots bound per submesh (`DrawManager.applyMaterialTextures`): base color, normal, specular.
  `roughnessTexture`, `metallicTexture`, `ambientOcclusionTexture` and `opacityTexture` are loaded and
  never bound.
- Which dialect each aircraft uses (`ModelLibrary.makeLibrary`): F-16 `f16r.obj` and F-18 `FA-18F.obj`
  (MTL); cgtrader F-22, Sketchfab F-22 and Sketchfab F-35 `.usdz` (USD).
- Older docs: the asset-pipeline rule's "Material color extraction" note is now qualified (see 1.6). The
  shading doc's Step 6 bullet "assign an authored specular / shininess even when it is zero" should read
  "when its type is `.float3` / when `Ns` is present", because USD's scalar `specular` 0 is a placeholder,
  not an authored zero.

### 2.2 Recommended approach

- **Simple version first:**
  1. First-wins for `.baseColor` values in `populateMaterial` (one condition; fixes every untextured USD
     material). A Metal-free test can build an `MDLMaterial` with two `.baseColor` float3 properties and
     assert that the first one lands in `properties.color`, provided `Material.init` touches no texture
     (it calls `TextureLoader` only for string / URL / texture properties).
  2. Type checks in `setProperties`: `.specular` only for `.float3`; `.specularExponent` present →
     `max(Ns, 1)` and strength 0 when `Ns < 1`; `.roughness` only when no exponent exists and the property
     is a float, through `exponent = clamp(2 / roughness⁴ − 2, 1, 1024)`.
  3. Stop reading `.emission`; leave `ambient` and `diffuse` with their deprecation comments (kept for the
     legacy Phong path, per the project rule).
  4. Pass the dialect into `Material.init` from `ObjModel` / `UsdModel` (or read the asset URL's extension
     in `Submesh`) so the two ignore rules are explicit rather than inferred from property types.
- **Optimized version later:** a metallic-roughness path (GGX + Schlick, sampled roughness / metallic /
  AO maps, emission in the G-buffer `lighting` target). It changes fidelity, not speed. Keep Blinn-Phong
  as the reference and compare on the deterministic `setColor` objects.
- **Runtime selection:** a `ShadingModel` enum on `RendererType` or `Preferences` is the natural place once
  the PBR path exists; the Blinn-Phong struct stays the interchange format (PBR needs roughness +
  metallic + F0, so `MaterialProperties` grows two floats then).

### 2.3 Suggested milestones

1. First-wins base color — observable result: the Sketchfab F-22 canopy tints orange at 0.6 opacity and
   the HUD glass green in every renderer; `swift scripts/inspect_mdl_materials.swift --repo-models` prints
   no `MISMATCH` line once the script's diagnostic is pointed at the new rule.
2. Dialect-aware specular import (type checks, `Ns < 1`, roughness → exponent) — observable result: the
   F-16 highlight about 17° wide, the sphere's about 4.5°, the F-22 cockpit interior (roughness 0.7)
   broader than the airframe default; a matte MTL test material shows no highlight.
3. Emission term in the forward paths, then the tiled `lighting` target — observable result: the F-22
   landing lights read white in shadow; nothing else changes (the F-18 and F-35 emissive maps are black).

### 2.4 Risks and pitfalls

| Symptom | Likely cause | How to check |
|---|---|---|
| An OBJ model glows or is washed out white | `.emission` (= `Ka 1 1 1`) used as emission | `inspect_mdl_materials.swift`: emission (1, 1, 1) on an `.obj` |
| Untextured USD parts are mid-gray | last-wins base color kept Model I/O's 0.18 default | the script's `MISMATCH` diagnostic |
| Ambient goes black on OBJ models after wiring AO | the `.ambientOcclusion` scalar the OBJ importer adds is 0.0 | the script: `ao = 0` on every OBJ material |
| USD aircraft lose their highlight | `.specular` scalar 0 accepted as an authored strength | type check `.float3` |
| An OBJ material's `Ns` is replaced by an exponent of about 1 | roughness → exponent applied to the 0.9 default the OBJ importer adds | only derive when no `.specularExponent` exists |
| F-18 canopy opaque | `Tr` is dropped, only `d` sets opacity | the F-18 Glass material has no `.opacity` property |
| Highlights differ between a canopy and the skin around it | forward passes use the submesh material, the deferred sun passes a shared strength / exponent | Appendix B, items 4 and 5 |

## Open questions

- Should the importer trust `Ks 1 1 1` from the F-16 and F-18 (faithful, plasticky) or scale MTL strengths
  toward the 0.25 default (nicer, but hides the asset's values)? Recommendation: faithful import; fix the
  asset if it looks wrong.
- Per-material specular in the deferred passes: the tiled G-buffer's unused `normal.w` (strength only) or
  a layout change (strength + exponent)?
- Should `MaterialProperties.specular` stay a `float3` (tinted highlights, which the forward paths could
  use) or become a scalar strength, given the G-buffer carries one channel?

## Appendix A — Measured mappings

Produced by `swift scripts/inspect_mdl_materials.swift --synthetic --repo-models` on 2026-09-21. The
script also prints, per property, whether it is the scattering function's own object or one the importer
added; on OBJ files `baseColor` and `emission` are the scattering function's objects filled in place,
while `specular`, `specularExponent`, `opacity`, `roughness`, `metallic` and `ao` are importer-added.

### A.1 MTL key → Model I/O property (OBJ importer)

| MTL | Semantic | Property name | Type when authored | When absent |
|---|---|---|---|---|
| `Kd` / `map_Kd` | `.baseColor` | baseColor | float3 / string → texture (one merged property; `float3Value` still holds `Kd`) | not tested (every repo file has `Kd`) |
| `Ka` / `map_Ka` | `.emission` | emission | float3 / string → texture | `.color` black |
| `Ke` / `map_Ke` | dropped | | | |
| `Ks` / `map_Ks` | `.specular` | specular | float3 / string → texture | `.float` 0 |
| `Ns` / `map_Ns` | `.specularExponent` | specularExponent | float / string → texture | no property |
| `d` / `map_d` | `.opacity` | opacity | float / string → texture | no property |
| `Tr` | dropped | | | |
| `Ni` | `.materialIndexOfRefraction` | indexOfRefraction | float | float 1.0 |
| `bump`, `map_bump` | `.tangentSpaceNormal` | bump | string → texture (the last line wins) | no property |
| `disp` | `.displacement` | displacement | string | no property |
| `illum` | dropped | | | |
| (not in the file) | `.subsurface` 0, `.metallic` 0, `.specularTint` 0, `.roughness` **0.9**, `.anisotropicRotation` 0, `.sheen` 0.05, `.sheenTint` 0, `.clearcoat` 0, `.clearcoatGloss` 0, `.interfaceIndexOfRefraction` 1.0, `.ambientOcclusion` (`ao`) **0.0**, `.ambientOcclusionScale` 1.0 | | added to every OBJ material | |

Precedence checks: `Ka` + `Ke` → emission = `Ka`; `Ke` only → the black default; `d` + `Tr` → opacity =
`d`; `Tr` only → no opacity; `illum 1` changes nothing.

### A.2 UsdPreviewSurface input → Model I/O property (USD importer)

| USD input | Semantic | Authored property (first in `properties(with:)`) | Model I/O default with the same semantic |
|---|---|---|---|
| diffuseColor | `.baseColor` | diffuseColor (texture or float3) | baseColor float3 (0.18, 0.18, 0.18) |
| emissiveColor | `.emission` | emissiveColor (texture or float3) | emission float3 0 |
| metallic, roughness | `.metallic`, `.roughness` | metallic, roughness (texture or float) | — |
| occlusion | `.ambientOcclusion` | occlusion float 1.0 | ambientOcclusion float 0.0 |
| opacity | `.opacity` | opacity float | — |
| ior | `.materialIndexOfRefraction` | ior | materialIndexOfRefraction 1.0 |
| normal | `.tangentSpaceNormal` | normal (texture, or float3 (0, 0, 1) when unset) | — |
| clearcoat, clearcoatRoughness | `.clearcoat`, `.none` | clearcoat, clearcoatRoughness | clearcoatGloss 0.99 |
| specularColor | not present in any repo file | specular `.float` 0 (placeholder) | — |
| — | `.specularExponent` | never present | — |

The authored-first order was checked through `properties(with:)` for `.baseColor`, `.emission` and
`.ambientOcclusion`; by-index enumeration lists the defaults first.

### A.3 The repo's materials

| Model (dialect) | Material | What arrives |
|---|---|---|
| `f16r.obj` (F-16, MTL) | F16s.003, F16t.003 | emission (1, 1, 1) from `Ka`; specular (1, 1, 1); exponent 16; opacity 1; `Ke 0` dropped; base color textures 1024² and 256×512 |
| `FA-18F.obj` (F-18, MTL) | Paint, Glass | emission (0.1, 0.1, 0.1); specular (1, 1, 1); exponent 80; no opacity (`Tr` dropped); Paint texture 2048², Glass `Kd` (1, 1, 1) |
| `Temple.obj` (MTL) | structure, tree | base color, specular, emission (= `map_Ka`, the base color map again) and normal textures; exponent 10; opacity 1 |
| `sphere.obj`, `quad.obj` (MTL) | Sphere, None | emission (1, 1, 1); specular 0.5 and 1.0; exponent 225 and 200 |
| `F-22_Raptor.usdz` (Sketchfab, USD) | f22a_airframe | diffuseColor, roughness, metallic, normal textures 2048²; specular float 0; occlusion 1; emissiveColor 0; no exponent |
| | Glass | diffuseColor (1.0, 0.438, 0.066), opacity 0.6, metallic 1, roughness 0 |
| | HudGlass, f22a_landingLights, f22a_cockpit | diffuseColor (0.011, 0.286, 0.0); (0.8, 0.8, 0.8) with emissiveColor (1, 1, 1); texture with roughness 0.7 |
| `F-35A_Lightning_II.usdz` (Sketchfab, USD) | mat_4 … mat_15 | diffuseColor, roughness, metallic, normal textures 1024²; emissiveColor 0 |
| `cgtrader_F22.usdz` (USD) | F22 | diffuseColor texture, roughness 0.5, metallic texture, ior 1.5, clearcoatRoughness 0.03 |
| `FA-18F.usdz` (RealityConverter, USD) | Paint | emissiveColor texture: mean (0.3, 0.2, 0.1) of 255, a few texels at 255 |
| `F35_JSF.usdc` (cgtrader, USD) | Body, Interior, Jet_Glass | emissive textures mean about 0 (max 225 and 255); Jet_Glass is a plain `MDLScatteringFunction` with a `.color` white base color and no opacity |

Engine result today for every USD material: `properties.color` = (0.18, 0.18, 0.18) (last-wins), while
`property(with: .baseColor)` returns `diffuseColor`.

## Appendix B — Review of the Step 6 working tree (2026-09-21)

Checked against the shading doc's Step 6 bullets and landing order. Comments were added where noted; no
code was changed by the review.

1. `MetalTypes.swift` defaults (0.25, 0.25, 0.25) and 32 — correct. Comment added explaining the four
   fields the shaders read and the two legacy ones.
2. `GBuffer.metal` — `material.color` fallback and `material.specular.r` into `albedo_specular.w` —
   correct. Comments added.
3. `Base.metal`, `OrderIndependentTransparency.metal`, `SinglePassDeferredTransparency.metal`,
   `TiledDeferredTransparency.metal` — `material.specular.r` / `material.shininess` — correct; the
   stale "Step 6 will …" comments rewritten.
4. `TiledDeferredDirectionalLight.metal` — the new `MaterialProperties` parameter is bound at
   `TFSBufferIndexMaterial` by nothing in the light stage. The full-screen triangle is encoded in the same
   render encoder right after `DrawOpaque` (`TiledDeferredRenderer.encodeGBufferStage` then
   `encodeLightingStage`), so the fragment reads the bytes `DrawManager.drawSubmeshes` set for the LAST
   opaque submesh. Every tiled pixel shares that submesh's strength and exponent, and which submesh is last
   depends on registration order (an F-16 material gives 1.0 / 16, a `setColor` object 0.25 / 32). Not a
   validation error, since the buffer is bound, but not the per-material specular it looks like. Fixes:
   bind a known `MaterialProperties` in each tiled renderer's `encodeDirectionalLightStage`, or the shading
   doc's Step 2 option (strength in `normal.w`). Comment added on the function.
5. `DirectionalLight.metal` — not switched: still `DEFAULT_SPECULAR_STRENGTH` (0) and `DEFAULT_SHININESS`
   (1), so the single-pass renderer draws no highlight while the tiled and OIT paths do. Landing-order
   step 2 for this file is `specularStrength = GBuffer.albedo_specular.a` plus `DEFAULT_SHININESS = 32`.
   Comment updated.
6. `Material.swift` `.roughness` case — dead (`.roughness` is not in the `semantics` list passed from
   `init`) and, when enabled, wrong: it assigns the derived exponent to `specular` (the strength) instead
   of `shininess`; it computes `2 / roughness² − 2` instead of `2 / roughness⁴ − 2` (roughness 0.5 → 6,
   not 30); it would run on every OBJ material's 0.9 default and replace the authored `Ns` with about 1;
   no clamp. FIXME comment added with the four corrections.
7. Not yet done from the Step 6 bullets: the legacy comments on `ambient` / `diffuse` / `.emission`
   (added now); "assign an authored zero specular" (see 2.1's qualification: only a `.float3` zero is
   authored).
8. Checks executed: `swift scripts/inspect_mdl_materials.swift --synthetic --repo-models`,
   `swift scripts/blinn_phong_roughness_table.swift`, the macOS Debug build after the comment edits. Not
   executed: the test suite, an in-app comparison of the renderers.

## References

### Origin sources
- Bui Tuong Phong, "Illumination for Computer Generated Pictures", Communications of the ACM, 1975; James
  Blinn, "Models of Light Reflection for Computer Synthesized Pictures", SIGGRAPH 1977 — the ambient +
  Lambert + specular model and the half-vector form the shared shading function implements.
- Wavefront Technologies, MTL file format specification — `Ka`, `Kd`, `Ks`, `Ns` ("defines the focus of
  the specular highlight", "normally range from 0 to 1000"), `d` ("1.0 is fully opaque"), and `illum`
  0 / 1 / 2 ("Blinn's interpretation of Phong's specular illumination model"). Mirror:
  http://paulbourke.net/dataformats/mtl/ (fetched 2026-09-21).
- Pixar, UsdPreviewSurface Specification — inputs, defaults (diffuseColor 0.18, roughness 0.5, occlusion
  1, ior 1.5, normal (0, 0, 1)), the specular vs metallic workflows, "emissiveColor: Emissive component".
  https://openusd.org/release/spec_usdpreviewsurface.html (fetched 2026-09-21).
- Brian Karis, "Specular BRDF Reference", 2013 — α = roughness², D_Blinn with exponent 2/α² − 2.
  http://graphicrants.blogspot.com/2013/08/specular-brdf-reference.html (fetched 2026-09-21).
- Brent Burley, "Physically-Based Shading at Disney", SIGGRAPH 2012 course — the parameter set
  `MDLPhysicallyPlausibleScatteringFunction` copies (subsurface, metallic, specular, specularTint,
  roughness, anisotropic, sheen, sheenTint, clearcoat, clearcoatGloss).
  https://disneyanimation.com/publications/physically-based-shading-at-disney/ [unverified: not re-fetched]

### Detailed explanations
- Apple, `MDLMaterial.h` (ModelIO.framework headers, macOS 27 SDK): `MDLMaterialSemantic`,
  `MDLMaterialPropertyType`, `MDLScatteringFunction` ("Lambertian, with a Blinn-Phong specular response.
  Specular power for Blinn-Phong can be derived from the roughness property using an approximation."),
  the `propertyWithSemantic:` / `propertiesWithSemantic:` contracts, "floatN property … Rec 709 color".
  Path: `$(xcrun --show-sdk-path)/System/Library/Frameworks/ModelIO.framework/Headers/MDLMaterial.h`
  (read 2026-09-21).
- Apple, MDLMaterialSemantic reference — https://developer.apple.com/documentation/modelio/mdlmaterialsemantic
  (the enum cases; the header above holds the useful comments).
- Kodeco, Metal by Tutorials, "Maps & Materials" — v3 chapter 11:
  https://www.kodeco.com/books/metal-by-tutorials/v3.0/chapters/11-maps-materials; v2 chapter 7:
  https://www.kodeco.com/books/metal-by-tutorials/v2.0/chapters/7-maps-materials — the `property(with:)`
  plus type-check import pattern. Code: https://github.com/kodecocodes/met-materials.

### Reference implementations
- three.js — `examples/jsm/loaders/MTLLoader.js`, `createMaterial_` (JavaScript): the MTL → Phong material
  table, `ka` unused, `tr` inverted.
  https://github.com/mrdoob/three.js/blob/dev/examples/jsm/loaders/MTLLoader.js (fetched 2026-09-21).
- Apple, "Rendering a scene with deferred lighting in Swift" (and the Objective-C original) — the mesh
  loader reading base color, specular and tangent-space normal semantics into three texture slots; the
  Temple asset. https://developer.apple.com/documentation/metal/rendering-a-scene-with-deferred-lighting-in-swift
  (page title checked 2026-09-21; code from prior knowledge).
- This repo — `scripts/inspect_mdl_materials.swift` (the probe; Swift),
  `scripts/blinn_phong_roughness_table.swift` (the numbers),
  `ToyFlightSimulator Shared/AssetPipeline/Thumbnails/AircraftThumbnailGenerator.swift`
  (`sanitizeObjMaterials`, the SceneKit symptom of the `Ka` mapping).

### Engine and simulator documentation
- Model I/O: no public documentation of the OBJ or USD importer mappings exists; everything in Appendix A
  is measured behavior of the macOS 27 SDK on 2026-09-21.

### Non-URL references
- Phong 1975 and Blinn 1977 as above; Real-Time Rendering, 4th edition, chapter 9 (Physically Based
  Shading) for the normalization the engine's Blinn-Phong lacks. [unverified page numbers]

Attribution notes: the `Ka` → `.emission` behavior is Apple's implementation choice with no published
rationale; the "first-wins" rule is this document's adaptation of the header's `propertyWithSemantic:`
contract to the observed ordering.
