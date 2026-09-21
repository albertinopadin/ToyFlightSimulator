//
//  TiledDeferredTransparency.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/14/24.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"
#import "ShaderHelpers.h"
#import "Lighting.metal"

vertex VertexOut
tiled_deferred_transparency_vertex(VertexIn                in              [[ stage_in ]],
                                   constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                   constant ModelConstants *modelConstants [[ buffer(TFSBufferModelConstants) ]],
                                   uint                    instanceId      [[ instance_id ]]) {
    ModelConstants modelInstance = modelConstants[instanceId];
    float4 worldPosition = modelInstance.modelMatrix * float4(in.position, 1);
    float4 position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition;

    VertexOut out {
        .position = position,
        .normal = in.normal,
        .uv = in.textureCoordinate,
        .worldPosition = worldPosition.xyz,
        .worldNormal = modelInstance.normalMatrix * in.normal,
        .worldTangent = modelInstance.normalMatrix * in.tangent,
        .worldBitangent = modelInstance.normalMatrix * in.bitangent,
        .instanceId = instanceId,
        .objectColor = modelInstance.objectColor,
        .useObjectColor = modelInstance.useObjectColor
    };
    return out;
}

fragment float4
tiled_deferred_transparency_fragment(
                         VertexOut                 in                [[ stage_in ]],
                constant SceneConstants            &sceneConstants   [[ buffer(TFSBufferIndexSceneConstants) ]],
                constant LightData                 &lightData        [[ buffer(TFSBufferDirectionalLightData) ]],
                constant MaterialProperties        &material         [[ buffer(TFSBufferIndexMaterial) ]],
                constant MaterialTextureTransforms &uvXforms         [[ buffer(TFSBufferIndexMaterialTextureTransforms) ]],
                sampler                            sampler2d         [[ sampler(0) ]],
                texture2d<half>                    baseColorTexture  [[ texture(TFSTextureIndexBaseColor) ]],
                depth2d_array<float>               shadowArray       [[ texture(TFSTextureIndexShadow) ]]) {
    // Forward-lit transparency (Step 5b of the shading doc) so the F-22 canopy shades like
    // the fuselage the G-buffer + sun pass lit. Serves all three tiled renderers: the MSAA pipelines bind this fragment too.
    // Every extra binding comes from earlier in the SAME encoder: SceneManager sets the
    // scene constants and the first sun's LightData for the fragment stage at the start
    // of the pass, and the G-buffer stage binds the shadow array at texture slot 3.
    // DrawManager's per-submesh material textures use slots 0-2, so none is clobbered.
    float2 baseUV = in.uv;
    if (uvXforms.hasTextureTransforms) {
        baseUV = ApplyUVTransform(in.uv, uvXforms.baseColorUVTransform);
    }

    float4 baseColor = ResolveBaseColor(in.useObjectColor,
                                        in.objectColor,
                                        material.color,
                                        baseColorTexture,
                                        sampler2d,
                                        baseUV);
    
    // World space throughout, like the tiled G-buffer: N, L (light.direction) and V share
    // one frame. No normal map on this path yet.
    float3 unitNormal = normalize(in.worldNormal);
    float3 toCamera = normalize(sceneConstants.cameraPosition - in.worldPosition);
    // Cascade selection keys on view-space depth (z after the view matrix), the same metric
    // the G-buffer stage passes from its eye-space position interpolant.
    float fragViewSpaceDepth = (sceneConstants.viewMatrix * float4(in.worldPosition, 1)).z;
    // Raw PCF visibility, 0 (fully shadowed) .. 1; it scales only the direct light.
    float litFraction = Lighting::CalculateShadow(in.worldPosition,
                                                  fragViewSpaceDepth,
                                                  in.worldNormal,
                                                  lightData,
                                                  shadowArray);
    
    // Landing-order step 1: specular off. Step 6 switches DEFAULT_SPECULAR_STRENGTH to
    // material.specular.r; with today's defaults (1.0, shininess 2) the canopy would get a
    // white N.H^2 lobe, see material_fragment in Base.metal.
    float3 litColor = Lighting::ShadeDirectionalBlinnPhong(baseColor.rgb,
                                                           unitNormal,
                                                           lightData.direction,
                                                           toCamera,
                                                           lightData,
                                                           Lighting::DEFAULT_SPECULAR_STRENGTH,
                                                           material.shininess,
                                                           litFraction);
    
    // Straight alpha, NOT premultiplied: this PSO blends with sourceAlpha /
    // oneMinusSourceAlpha (RenderPipelineState.enableBlending), so the hardware applies the
    // opacity. Premultiplying here as well would apply it twice.
    return float4(litColor, ResolveOpacity(baseColor.a, material.opacity));
}
