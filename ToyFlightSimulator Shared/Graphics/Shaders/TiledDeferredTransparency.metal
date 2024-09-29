//
//  TiledDeferredTransparency.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/14/24.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"

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

fragment float4
tiled_deferred_transparency_fragment(VertexOut                   in                  [[ stage_in ]],
                                     constant MaterialProperties &material           [[ buffer(TFSBufferIndexMaterial) ]],
                                     sampler                     sampler2d           [[ sampler(0) ]],
                                     texture2d<half>             baseColorTexture    [[ texture(TFSTextureIndexBaseColor) ]]) {
    float4 color = material.color;
    
    if (in.useObjectColor) {
        color = in.objectColor;
    } else if (!is_null_texture(baseColorTexture)) {
        color = float4(baseColorTexture.sample(sampler2d, in.uv));
    }
    
    if (color.a < 1.0 && material.opacity < 1.0) {
        color.a = max(color.a, material.opacity);
    } else {
        color.a = min(color.a, material.opacity);
    }
    
    return color;
}
