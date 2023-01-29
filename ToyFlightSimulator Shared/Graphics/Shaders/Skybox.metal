//
//  Skybox.metal
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 1/25/23.
//

#include <metal_stdlib>
using namespace metal;

#include "TFSShaderTypes.h"
#include "Shared.metal"

struct SkyboxVertex
{
    float4 position [[ attribute(TFSVertexAttributePosition) ]];
    float3 normal   [[ attribute(TFSVertexAttributeNormal) ]];
};

struct SkyboxInOut
{
    float4 position [[ position ]];
    float3 texcoord;
};

vertex SkyboxInOut skybox_vertex(SkyboxVertex in [[ stage_in ]],
                                 constant SceneConstants &sceneConstants [[ buffer(1) ]],
                                 constant ModelConstants &modelConstants [[ buffer(2) ]])
{
    SkyboxInOut out;
    float4 worldPosition = modelConstants.modelMatrix * in.position;
    out.position = sceneConstants.projectionMatrix * sceneConstants.skyViewMatrix * worldPosition;
    out.texcoord = in.normal;
    return out;
}

fragment half4 skybox_fragment(SkyboxInOut in [[ stage_in ]],
                               texturecube<float> skyboxTexture [[ texture(TFSTextureIndexBaseColor) ]]) {
    constexpr sampler linearSampler(mip_filter::linear, mag_filter::linear, min_filter::linear);

    float4 color = skyboxTexture.sample(linearSampler, in.texcoord);
    return half4(color);
}
