//
//  TiledDeferredTransparency.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/13/24.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"

vertex VertexOut
tiled_deferred_transparency_vertex(VertexIn                in              [[ stage_in ]],
                                   constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                   constant ModelConstants &modelConstants [[ buffer(TFSBufferModelConstants) ]],
                                   constant LightData      &lightData      [[ buffer(TFSBufferDirectionalLightData) ]]) {
    float4 worldPosition = modelConstants.modelMatrix * float4(in.position, 1);
    float4 position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition;
    
    VertexOut out {
        .position = position,
        .normal = in.normal,
        .uv = in.textureCoordinate,
        .worldPosition = worldPosition.xyz / worldPosition.w,
        .worldNormal = modelConstants.normalMatrix * in.normal,
        .worldTangent = modelConstants.normalMatrix * in.tangent,
        .worldBitangent = modelConstants.normalMatrix * in.bitangent,
        .shadowPosition = lightData.shadowViewProjectionMatrix * worldPosition
    };
    return out;
}

fragment float4
tiled_deferred_transparency_fragment(VertexOut                   in                  [[ stage_in ]],
                                     constant MaterialProperties &material           [[ buffer(TFSBufferIndexMaterial) ]],
                                     sampler                     sampler2d           [[ sampler(0) ]],
                                     texture2d<half>             baseColorTexture    [[ texture(TFSTextureIndexBaseColor) ]]) {
    float4 color = material.color;
    
    if (!material.useMaterialColor && !is_null_texture(baseColorTexture)) {
        color = float4(baseColorTexture.sample(sampler2d, in.uv));
    }
    
    color.a = material.opacity;
    return color;
}
