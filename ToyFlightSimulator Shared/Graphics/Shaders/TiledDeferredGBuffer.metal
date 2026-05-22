//
//  TiledDeferredGBuffer.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/2/24.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"
#import "Lighting.metal"

//constant bool hasSkeleton [[ function_constant(0) ]];

vertex VertexOut
tiled_deferred_gbuffer_vertex(
           VertexIn       in              [[ stage_in ]],
  constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
  constant ModelConstants *modelConstants [[ buffer(TFSBufferModelConstants) ]],
           uint           instanceId      [[ instance_id ]]) {
    ModelConstants modelInstance = modelConstants[instanceId];
    float4 worldPosition = modelInstance.modelMatrix * float4(in.position, 1);
    float4 eyePosition   = sceneConstants.viewMatrix * worldPosition;
    float3 worldXYZ      = worldPosition.xyz / worldPosition.w;

    VertexOut out {
        .position       = sceneConstants.projectionMatrix * eyePosition,
        .normal         = in.normal,
        .uv             = in.textureCoordinate,
        .worldPosition  = worldXYZ,
        .worldNormal    = modelInstance.normalMatrix * in.normal,
        .worldTangent   = modelInstance.normalMatrix * in.tangent,
        .worldBitangent = modelInstance.normalMatrix * in.bitangent,
        // Camera-relative WORLD-SPACE distance. Used by
        // Lighting::CalculateShadow's cascade selection. Computing
        // `distance(worldXYZ, cameraPosition)` instead of `|eye.z|` avoids
        // float32 cancellation in `view * worldPos` at large world coords
        // (Sterbenz's lemma keeps the subtraction exact) AND avoids the
        // mixed-sign-clip.w rasterizer issue on huge meshes like the ground
        // quad (whose corners straddle the camera). See
        // debugging/claude/csm_select_cascade_drift.md.
        // Matched on CPU: cascade splits multiplied by cameraScale.
        .viewSpaceDepth = distance(worldXYZ, sceneConstants.cameraPosition),
        .instanceId     = instanceId,
        .objectColor    = modelInstance.objectColor,
        .useObjectColor = modelInstance.useObjectColor
    };
    return out;
}

vertex VertexOut
tiled_deferred_gbuffer_animated_vertex(
           VertexIn       in              [[ stage_in ]],
  constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
  constant ModelConstants *modelConstants [[ buffer(TFSBufferModelConstants) ]],
  constant float4x4       *jointMatrices  [[ buffer(TFSBufferIndexJointBuffer) ]],
           uint           instanceId      [[ instance_id ]]) {
    ModelConstants modelInstance = modelConstants[instanceId];
    float4 position = float4(in.position, 1);
    float4 normal = float4(in.normal, 0);

    if (jointMatrices != nullptr) {
        float4 weights = in.jointWeights;
        ushort4 joints = in.joints;

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
    float4 eyePosition   = sceneConstants.viewMatrix * worldPosition;
    float3 worldXYZ      = worldPosition.xyz / worldPosition.w;

    VertexOut out {
        .position       = sceneConstants.projectionMatrix * eyePosition,
        .normal         = normal.xyz,
        .uv             = in.textureCoordinate,
        .worldPosition  = worldXYZ,
        .worldNormal    = modelInstance.normalMatrix * in.normal,
        .worldTangent   = modelInstance.normalMatrix * in.tangent,
        .worldBitangent = modelInstance.normalMatrix * in.bitangent,
        // See _vertex above for the rationale on `distance` vs `|eye.z|`.
        .viewSpaceDepth = distance(worldXYZ, sceneConstants.cameraPosition),
        .instanceId     = instanceId,
        .objectColor    = modelInstance.objectColor,
        .useObjectColor = modelInstance.useObjectColor
    };
    return out;
}

fragment GBufferOut
tiled_deferred_gbuffer_fragment(VertexOut                          in                  [[ stage_in ]],
                                constant SceneConstants            &sceneConstants     [[ buffer(TFSBufferIndexSceneConstants) ]],
                                constant MaterialProperties        &material           [[ buffer(TFSBufferIndexMaterial) ]],
                                constant MaterialTextureTransforms &uvXforms           [[ buffer(TFSBufferIndexMaterialTextureTransforms) ]],
                                constant LightData                 &lightData          [[ buffer(TFSBufferDirectionalLightData) ]],
                                sampler                            sampler2d           [[ sampler(0) ]],
                                texture2d<half>                    baseColorTexture    [[ texture(TFSTextureIndexBaseColor) ]],
                                texture2d<half>                    normalTexture       [[ texture(TFSTextureIndexNormal) ]],
                                depth2d_array<float>               shadowArray         [[ texture(TFSTextureIndexShadow) ]]) {
    float2 baseUV   = in.uv;
    float2 normalUV = in.uv;
    if (uvXforms.hasTextureTransforms) {
        baseUV   = ApplyUVTransform(in.uv, uvXforms.baseColorUVTransform);
        normalUV = ApplyUVTransform(in.uv, uvXforms.normalUVTransform);
    }

    float4 color = material.color;

    if (in.useObjectColor) {
        color = in.objectColor;
    } else if (!is_null_texture(baseColorTexture)) {
        color = float4(baseColorTexture.sample(sampler2d, baseUV));
    }

    // Per-fragment world-space distance from camera. Computed here rather
    // than as a per-vertex attribute because `distance` is non-linear in
    // eye space, and the rasterizer interpolating the per-vertex value
    // breaks for huge meshes that span the near plane (e.g. the ground
    // quad — the previous fragment-shader read of `in.viewSpaceDepth`
    // produced a static dim patch instead of tracking the camera). The
    // rasterizer interpolates `worldPosition` linearly in eye space, so
    // recomputing the distance here gives a correct per-fragment value.
    // See debugging/claude/csm_select_cascade_drift.md.
    float fragViewSpaceDepth = distance(in.worldPosition, sceneConstants.cameraPosition);

    color.a = Lighting::CalculateShadow(in.worldPosition,
                                        fragViewSpaceDepth,
                                        in.worldNormal,
                                        lightData,
                                        shadowArray);

    float4 normal = float4(normalize(in.worldNormal), 1.0);

    if (!in.useObjectColor && !is_null_texture(normalTexture)) {
        normal = float4(normalTexture.sample(sampler2d, normalUV));
    }
    
    GBufferOut out {
        .albedo = color,
        .normal = normal,
        .position = float4(in.worldPosition, 1.0)
    };
    return out;
}
