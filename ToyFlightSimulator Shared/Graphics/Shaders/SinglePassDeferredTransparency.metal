//
//  SinglePassDeferredTransparency.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/15/24.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"

vertex VertexOut
single_pass_deferred_transparency_vertex(   VertexIn       in              [[ stage_in ]],
                                   constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                   constant ModelConstants *modelConstants [[ buffer(TFSBufferModelConstants) ]],
                                   uint                    instanceId      [[ instance_id ]]) {
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
        // Camera-relative world-space distance — see TiledDeferredGBuffer.metal.
        .viewSpaceDepth = distance(worldXYZ, sceneConstants.cameraPosition),
        .instanceId     = instanceId,
        .objectColor    = modelInstance.objectColor,
        .useObjectColor = modelInstance.useObjectColor
    };
    return out;
}

fragment float4
single_pass_deferred_transparency_fragment(   VertexOut                          in                  [[ stage_in ]],
                                     constant MaterialProperties                 &material           [[ buffer(TFSBufferIndexMaterial) ]],
                                     constant MaterialTextureTransforms          &uvXforms           [[ buffer(TFSBufferIndexMaterialTextureTransforms) ]],
                                     sampler                                     sampler2d           [[ sampler(0) ]],
                                     texture2d<half>                             baseColorTexture    [[ texture(TFSTextureIndexBaseColor) ]]) {
    float2 baseUV = in.uv;
    if (uvXforms.hasTextureTransforms) {
        baseUV = ApplyUVTransform(in.uv, uvXforms.baseColorUVTransform);
    }

    float4 color = material.color;

    if (in.useObjectColor) {
        color = in.objectColor;
    } else if (!is_null_texture(baseColorTexture)) {
        color = float4(baseColorTexture.sample(sampler2d, baseUV));
    }
    
    if (color.a < 1.0 && material.opacity < 1.0) {
        color.a = max(color.a, material.opacity);
    } else {
        color.a = min(color.a, material.opacity);
    }
    
    return color;
}
