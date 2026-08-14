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
        .worldPosition = worldPosition.xyz / worldPosition.w,
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
tiled_deferred_transparency_fragment(VertexOut                          in                  [[ stage_in ]],
                                     constant MaterialProperties        &material           [[ buffer(TFSBufferIndexMaterial) ]],
                                     constant MaterialTextureTransforms &uvXforms           [[ buffer(TFSBufferIndexMaterialTextureTransforms) ]],
                                     sampler                            sampler2d           [[ sampler(0) ]],
                                     texture2d<half>                    baseColorTexture    [[ texture(TFSTextureIndexBaseColor) ]]) {
    float2 baseUV = in.uv;
    if (uvXforms.hasTextureTransforms) {
        baseUV = ApplyUVTransform(in.uv, uvXforms.baseColorUVTransform);
    }

    float4 color = ResolveBaseColor(in.useObjectColor,
                                    in.objectColor,
                                    material.color,
                                    baseColorTexture,
                                    sampler2d,
                                    baseUV);
    
    color.a = ResolveOpacity(color.a, material.opacity);
    
    return color;
}
