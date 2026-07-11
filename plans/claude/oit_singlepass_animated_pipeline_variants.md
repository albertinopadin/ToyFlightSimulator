# Animated pipeline variants for the OIT and SinglePassDeferred renderers

Status: **implemented** (2026-07-11). Landed as planned with no deviations: 3 new Metal vertex
functions, 3 `ShaderType` cases, 4 pipeline structs + `RenderPipelineStateType` cases,
`animatedVariant`/`isAnimatedVariant` extended, tests updated (`familiesWithoutAnimatedPipelinesMapToNil`
replaced by `oitAndSinglePassMapping` + `passesWithoutAnimatedPipelinesMapToNil`). Verified: macOS Debug
build, iOS Simulator build, scoped `RenderPipelineStateTypeAnimatedVariantTests` run (6/6 pass).
Manual OIT/SinglePass gear-animation check pending user verification.

## Context

Since the renderer-switch PSO fix (`645e307`), `DrawManager.SetupAnimation` derives each pass's skinned-mesh pipeline from `RenderPipelineStateType.animatedVariant`. OIT and SinglePassDeferred map to `nil` — their families have no animated pipelines in the library — so skinned meshes (the default scene's F-22, gear animation, control surfaces) render in **bind pose** under those renderers. This plan removes that limitation by adding the missing animated PSOs and the Metal vertex shaders behind them.

What "animated variant" means mechanically (verified against the existing pairs): the animated PSO is an exact clone of the base pass PSO **with only the vertex function swapped** for one that reads the joint palette (`constant float4x4 *jointMatrices [[ buffer(TFSBufferIndexJointBuffer) ]]`, bound by `SetupAnimation`) and does 4-influence linear-blend skinning. Same fragment function, formats, blending, sample count. Compare `TiledMSAAGBufferPipelineState` vs `TiledMSAAGBufferAnimatedPipelineState` (`TiledMSAAPipeline.swift:46-74`) — the diff is one line: `.TiledDeferredGBufferVertex` → `.TiledDeferredGBufferAnimatedVertex`.

Inventory of what's missing (verified):

| Pass PSO | Vertex fn today | Animated vertex fn | Exists? |
|---|---|---|---|
| `.OpaqueMaterial` (OIT opaque) | `base_vertex` (Base.metal:19) | — | **no** |
| `.OrderIndependentTransparent` (OIT transparent) | `base_vertex` (same fn) | — | **no** |
| `.SinglePassDeferredGBufferMaterial` | `gbuffer_vertex` (GBuffer.metal:40) | — | **no** |
| `.SinglePassDeferredTransparency` | `single_pass_deferred_transparency_vertex` | — | **no** |
| SinglePass shadows (`.ShadowGeneration`) | `shadow_vertex` | `shadow_animated_vertex` | **yes** — already mapped to `.TiledMSAAShadowAnimated` (shared cascade layout); nothing to do |

Both OIT mesh pipelines use the same `base_vertex`, so **three** new Metal vertex functions cover all four new PSOs.

## Design decisions

- **Skinning scope mirrors the existing animated shaders**: skin position and normal (normal with w = 0), leave tangent/bitangent unskinned — same scope as `tiled_deferred_gbuffer_animated_vertex` (TiledDeferredGBuffer.metal:41-85). One deliberate small divergence: the tiled shader feeds the *unskinned* normal into `.worldNormal` while putting the skinned one only in `.normal`; the new shaders use the **skinned** normal for every normal output, since those outputs feed lighting/shadow-bias. (Not retrofitting the tiled shader here — behavior parity for existing renderers.)
- Preserve `base_vertex`'s house idiom of transforming direction vectors with `float4(v, 1.0)` in `.surfaceNormal/.surfaceTangent/.surfaceBitangent` (a pre-existing quirk — translation leaks into normals for off-origin models; do not fix in this change, it would alter OIT's current shading).
- The `if (jointMatrices != nullptr)` guard matches the existing animated shaders (null joint buffer ⇒ rigid path).
- Vertex descriptor stays `.Simple` — it already carries `joints`/`jointWeights` attributes (the tiled animated pipelines use it).

## Diffs

### 1. Three new Metal vertex functions

**`ToyFlightSimulator Shared/Graphics/Shaders/Base.metal`** — add after `base_vertex` (line 43):

```metal
vertex RasterizerData base_animated_vertex(const VertexIn vIn [[ stage_in ]],
                                           constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                           constant ModelConstants *modelConstants [[ buffer(TFSBufferModelConstants) ]],
                                           constant float4x4 *jointMatrices [[ buffer(TFSBufferIndexJointBuffer) ]],
                                           uint instanceId [[ instance_id ]]) {
    ModelConstants modelInstance = modelConstants[instanceId];
    float4 position = float4(vIn.position, 1);
    float4 normal = float4(vIn.normal, 0);

    if (jointMatrices != nullptr) {
        float4 weights = vIn.jointWeights;
        ushort4 joints = vIn.joints;

        position = weights.x * (jointMatrices[joints.x] * position) +
                weights.y * (jointMatrices[joints.y] * position) +
                weights.z * (jointMatrices[joints.z] * position) +
                weights.w * (jointMatrices[joints.w] * position);

        normal = weights.x * (jointMatrices[joints.x] * normal) +
                weights.y * (jointMatrices[joints.y] * normal) +
                weights.z * (jointMatrices[joints.z] * normal) +
                weights.w * (jointMatrices[joints.w] * normal);
    }

    float4 worldPosition = modelInstance.modelMatrix * position;

    RasterizerData rd = {
        // Order of matrix multiplication is important here:
        .position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition,
        .color = vIn.color,
        .objectColor = modelInstance.objectColor,
        .textureCoordinate = vIn.textureCoordinate,
        .totalGameTime = sceneConstants.totalGameTime,
        .worldPosition = worldPosition.xyz,
        .toCameraVector = sceneConstants.cameraPosition - worldPosition.xyz,
        .surfaceNormal = normalize(modelInstance.modelMatrix * float4(normal.xyz, 1.0)).xyz,
        .surfaceTangent = normalize(modelInstance.modelMatrix * float4(vIn.tangent, 1.0)).xyz,
        .surfaceBitangent = normalize(modelInstance.modelMatrix * float4(vIn.bitangent, 1.0)).xyz,
        .instanceId = instanceId,
        .useObjectColor = modelInstance.useObjectColor
    };

    return rd;
}
```

**`ToyFlightSimulator Shared/Graphics/Shaders/GBuffer.metal`** — add after `gbuffer_vertex` (line 66):

```metal
vertex ColorInOut gbuffer_animated_vertex(VertexIn                   in              [[ stage_in ]],
                                          constant SceneConstants    &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                          constant ModelConstants    *modelConstants [[ buffer(TFSBufferModelConstants) ]],
                                          constant float4x4          *jointMatrices  [[ buffer(TFSBufferIndexJointBuffer) ]],
                                          uint                       instanceId      [[ instance_id ]]) {
    ModelConstants modelInstance = modelConstants[instanceId];
    float4 modelPosition = float4(in.position, 1.0);
    float4 normal = float4(in.normal, 0);

    if (jointMatrices != nullptr) {
        float4 weights = in.jointWeights;
        ushort4 joints = in.joints;

        modelPosition = weights.x * (jointMatrices[joints.x] * modelPosition) +
                weights.y * (jointMatrices[joints.y] * modelPosition) +
                weights.z * (jointMatrices[joints.z] * modelPosition) +
                weights.w * (jointMatrices[joints.w] * modelPosition);

        normal = weights.x * (jointMatrices[joints.x] * normal) +
                weights.y * (jointMatrices[joints.y] * normal) +
                weights.z * (jointMatrices[joints.z] * normal) +
                weights.w * (jointMatrices[joints.w] * normal);
    }

    float4 worldPosition = modelInstance.modelMatrix * modelPosition;
    float4 eyePosition = sceneConstants.viewMatrix * worldPosition;

    ColorInOut out = {
        .color = in.color,
        .objectColor = modelInstance.objectColor,
        .tex_coord = in.textureCoordinate,
        .position = sceneConstants.projectionMatrix * eyePosition,
        .worldPosition = worldPosition.xyz / worldPosition.w,
        .worldNormal = modelInstance.normalMatrix * normal.xyz,
        .eye_position = eyePosition.xyz,
        .tangent = half3(normalize(modelInstance.normalMatrix * in.tangent)),
        .bitangent = half3(-normalize(modelInstance.normalMatrix * in.bitangent)),
        .normal = half3(normalize(modelInstance.normalMatrix * normal.xyz)),
        .instanceId = instanceId,
        .useObjectColor = modelInstance.useObjectColor
    };

    return out;
}
```

**`ToyFlightSimulator Shared/Graphics/Shaders/SinglePassDeferredTransparency.metal`** — add after `single_pass_deferred_transparency_vertex` (line 36):

```metal
vertex VertexOut
single_pass_deferred_transparency_animated_vertex(   VertexIn       in              [[ stage_in ]],
                                            constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                            constant ModelConstants *modelConstants [[ buffer(TFSBufferModelConstants) ]],
                                            constant float4x4       *jointMatrices  [[ buffer(TFSBufferIndexJointBuffer) ]],
                                            uint                    instanceId      [[ instance_id ]]) {
    ModelConstants modelInstance = modelConstants[instanceId];
    float4 modelPosition = float4(in.position, 1);
    float4 normal = float4(in.normal, 0);

    if (jointMatrices != nullptr) {
        float4 weights = in.jointWeights;
        ushort4 joints = in.joints;

        modelPosition = weights.x * (jointMatrices[joints.x] * modelPosition) +
                weights.y * (jointMatrices[joints.y] * modelPosition) +
                weights.z * (jointMatrices[joints.z] * modelPosition) +
                weights.w * (jointMatrices[joints.w] * modelPosition);

        normal = weights.x * (jointMatrices[joints.x] * normal) +
                weights.y * (jointMatrices[joints.y] * normal) +
                weights.z * (jointMatrices[joints.z] * normal) +
                weights.w * (jointMatrices[joints.w] * normal);
    }

    float4 worldPosition = modelInstance.modelMatrix * modelPosition;

    VertexOut out {
        .position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition,
        .normal = normal.xyz,
        .uv = in.textureCoordinate,
        .worldPosition = worldPosition.xyz / worldPosition.w,
        .worldNormal = modelInstance.normalMatrix * normal.xyz,
        .worldTangent = modelInstance.normalMatrix * in.tangent,
        .worldBitangent = modelInstance.normalMatrix * in.bitangent,
        .instanceId = instanceId,
        .objectColor = modelInstance.objectColor,
        .useObjectColor = modelInstance.useObjectColor
    };
    return out;
}
```

### 2. `ToyFlightSimulator Shared/Graphics/Libraries/ShaderLibrary.swift`

Three new `ShaderType` cases (next to their families) + registrations in `makeLibrary()`:

```diff
     case BaseVertex
+    case BaseAnimatedVertex
```
```diff
     case SinglePassDeferredGBufferVertex
+    case SinglePassDeferredGBufferAnimatedVertex
```
```diff
     case SinglePassDeferredTransparencyVertex
+    case SinglePassDeferredTransparencyAnimatedVertex
```
```diff
         _library.updateValue(Shader(functionName: "base_vertex"), forKey: .BaseVertex)
+        _library.updateValue(Shader(functionName: "base_animated_vertex"), forKey: .BaseAnimatedVertex)
```
```diff
         _library.updateValue(Shader(functionName: "gbuffer_vertex"), forKey: .SinglePassDeferredGBufferVertex)
+        _library.updateValue(Shader(functionName: "gbuffer_animated_vertex"),
+                             forKey: .SinglePassDeferredGBufferAnimatedVertex)
```
```diff
         _library.updateValue(Shader(functionName: "single_pass_deferred_transparency_vertex"),
                              forKey: .SinglePassDeferredTransparencyVertex)
+        _library.updateValue(Shader(functionName: "single_pass_deferred_transparency_animated_vertex"),
+                             forKey: .SinglePassDeferredTransparencyAnimatedVertex)
```

### 3. Four new pipeline structs (clones, vertex fn swapped)

**`OrderIndependentTransparencyPipeline.swift`** — after `OpaqueMaterialRenderPipelineState` and `OrderIndependentTransparencyRenderPipelineState` respectively:

```swift
struct OpaqueMaterialAnimatedRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        let renderPipelineDescriptor = Self.GetOpaqueRenderPipelineDescriptor(vertexDescriptorType: .Simple,
                                                                              vertexShaderType: .BaseAnimatedVertex,
                                                                              fragmentShaderType: .MaterialFragment)

        renderPipelineDescriptor.label = "Opaque Material Animated Render"
        return createRenderPipelineState(descriptor: renderPipelineDescriptor)
    }()
}

struct OrderIndependentTransparencyAnimatedRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Transparent Animated Render") { descriptor in
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
            descriptor.vertexFunction = Graphics.Shaders[.BaseAnimatedVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.TransparentMaterialFragment]

            descriptor.colorAttachments[0].isBlendingEnabled = false
            descriptor.colorAttachments[0].writeMask = MTLColorWriteMask(rawValue: 0)
            descriptor.colorAttachments[0].pixelFormat = Preferences.MainPixelFormat

            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthPixelFormat
            descriptor.stencilAttachmentPixelFormat = .invalid
        }
    }()
}
```

**`SinglePassDeferredPipeline.swift`** — after `GBufferGenerationMaterialRenderPipelineState` and `TransparencyPipelineState` respectively:

```swift
struct GBufferGenerationMaterialAnimatedRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "GBuffer Generation Animated Stage") { descriptor in
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
            descriptor.vertexFunction = Graphics.Shaders[.SinglePassDeferredGBufferAnimatedVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.SinglePassDeferredGBufferFragmentMaterial]
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.stencilAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setRenderTargetPixelFormatsForSinglePassDeferredPipeline(descriptor: descriptor)
        }
    }()
}

struct TransparencyAnimatedPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Transparency Animated Stage") { descriptor in
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
            descriptor.vertexFunction = Graphics.Shaders[.SinglePassDeferredTransparencyAnimatedVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.SinglePassDeferredTransparencyFragment]
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setRenderTargetPixelFormatsForSinglePassDeferredPipeline(descriptor: descriptor)
            descriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
            descriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
            Self.enableBlending(colorAttachmentDescriptor: descriptor.colorAttachments[TFSRenderTargetLighting.index])
        }
    }()
}
```

### 4. `RenderPipelineStateLibrary.swift` — cases, registrations, mapping

```diff
     case OpaqueMaterial
+    case OpaqueMaterialAnimated
     case OrderIndependentTransparent
+    case OrderIndependentTransparentAnimated
```
```diff
     case SinglePassDeferredGBufferMaterial
+    case SinglePassDeferredGBufferMaterialAnimated
```
```diff
     case SinglePassDeferredTransparency
+    case SinglePassDeferredTransparencyAnimated
```
```diff
         _library.updateValue(OpaqueMaterialRenderPipelineState(), forKey: .OpaqueMaterial)
+        _library.updateValue(OpaqueMaterialAnimatedRenderPipelineState(), forKey: .OpaqueMaterialAnimated)
         _library.updateValue(OrderIndependentTransparencyRenderPipelineState(), forKey: .OrderIndependentTransparent)
+        _library.updateValue(OrderIndependentTransparencyAnimatedRenderPipelineState(),
+                             forKey: .OrderIndependentTransparentAnimated)
```
```diff
         _library.updateValue(GBufferGenerationMaterialRenderPipelineState(), forKey: .SinglePassDeferredGBufferMaterial)
+        _library.updateValue(GBufferGenerationMaterialAnimatedRenderPipelineState(),
+                             forKey: .SinglePassDeferredGBufferMaterialAnimated)
```
```diff
         _library.updateValue(TransparencyPipelineState(), forKey: .SinglePassDeferredTransparency)
+        _library.updateValue(TransparencyAnimatedPipelineState(), forKey: .SinglePassDeferredTransparencyAnimated)
```

Extend the mapping (and convert the growing `isAnimatedVariant` chain to a switch):

```diff
     var animatedVariant: RenderPipelineStateType? {
         switch self {
             case .TiledMSAAGBuffer, .TiledMSAATransparency:
                 return .TiledMSAAGBufferAnimated
             case .TiledDeferredGBuffer, .TiledDeferredTransparency:
                 return .TiledDeferredGBufferAnimated
             case .TiledMSAAShadow, .TiledDeferredShadow, .ShadowGeneration:
                 return .TiledMSAAShadowAnimated
+            case .OpaqueMaterial:
+                return .OpaqueMaterialAnimated
+            case .OrderIndependentTransparent:
+                return .OrderIndependentTransparentAnimated
+            case .SinglePassDeferredGBufferMaterial:
+                return .SinglePassDeferredGBufferMaterialAnimated
+            case .SinglePassDeferredTransparency:
+                return .SinglePassDeferredTransparencyAnimated
             default:
                 return nil
         }
     }

     /// True for exactly the animated PSOs SetupAnimation can have bound.
     var isAnimatedVariant: Bool {
-        self == .TiledMSAAGBufferAnimated
-            || self == .TiledDeferredGBufferAnimated
-            || self == .TiledMSAAShadowAnimated
+        switch self {
+            case .TiledMSAAGBufferAnimated, .TiledDeferredGBufferAnimated, .TiledMSAAShadowAnimated,
+                 .OpaqueMaterialAnimated, .OrderIndependentTransparentAnimated,
+                 .SinglePassDeferredGBufferMaterialAnimated, .SinglePassDeferredTransparencyAnimated:
+                return true
+            default:
+                return false
+        }
     }
```

No `DrawManager` or renderer changes: `SetupAnimation` already derives everything from the mapping, and all pass binds are tracked since `645e307`.

### 5. Test updates — `ToyFlightSimulatorTests/Graphics/RenderPipelineStateTypeAnimatedVariantTests.swift`

- `familiesWithoutAnimatedPipelinesMapToNil` currently asserts the four OIT/SinglePass pass types map to nil — replace with a new test asserting their new mappings, keeping `.Composite`/`.TiledMSAAAverageResolve` (and add `.Final`, `.Blend`, `.TileRender`) as the nil cases.
- Extend `animatedVariantsAreTerminal` and `isAnimatedVariantMembership` with the four new animated cases.

## Verification

1. Builds: macOS Debug + iOS Simulator (Metal shader compilation is part of the build; a typo in the new shaders fails here).
2. Scoped tests: `-only-testing:"ToyFlightSimulatorTests/RenderPipelineStateTypeAnimatedVariantTests"`.
3. Manual, macOS app, Metal API validation ON:
   - Switch to **OIT**: toggle gear (`G`) — the gear must now animate (was bind pose); canopy transparency still correct; no validation asserts.
   - Switch to **SinglePassDeferred**: gear animates in the GBuffer view *and in its shadows* (shadow path was already animated via the shared PSO); transparency stage intact.
   - Re-check one tiled renderer (default) for no regression — mapping entries for tiled families are untouched.
   - Optional cold-launch legs into OIT/SinglePass (temporarily change the initial `rendererType`).

## Risks / notes

- All four new PSOs compile eagerly with the library on first access — a descriptor mistake `fatalError`s at startup with the pipeline label, so failures are loud and early.
- The three new shaders follow the existing skinning idiom, including its limits (tangent/bitangent unskinned; `base_vertex`'s `float4(v, 1.0)` normal transform preserved for OIT visual parity). Improving normal handling across all animated shaders would be a separate, visually-verified change.
- Independent of the `retire_renderstate_global_pass_context` plan, but both touch `animatedVariant`/`SetupAnimation`-adjacent code — land this one first (it only extends the mapping; the refactor then consumes it unchanged).
