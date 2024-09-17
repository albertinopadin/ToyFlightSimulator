//
//  Skybox.metal
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 1/25/23.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"

//struct SkyboxVertex
//{
//    float4 position [[ attribute(TFSVertexAttributePosition) ]];
//    float3 normal   [[ attribute(TFSVertexAttributeNormal) ]];
//};

struct SkyboxVertex
{
    float4 position [[ attribute(0) ]];
    float3 normal   [[ attribute(1) ]];
};

struct SkyboxInOut
{
    float4 position [[ position ]];
    float3 texcoord;
};

vertex SkyboxInOut skybox_vertex(SkyboxVertex               in              [[ stage_in ]],
                                 constant SceneConstants    &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                 constant ModelConstants    &modelConstants [[ buffer(TFSBufferModelConstants) ]]) {
    float4 worldPosition = modelConstants.modelMatrix * in.position;
    
    SkyboxInOut out = {
        .position = sceneConstants.projectionMatrix * sceneConstants.skyViewMatrix * worldPosition,
        .texcoord = in.normal
    };
    
    return out;
}

fragment half4 skybox_fragment(SkyboxInOut          in              [[ stage_in ]],
                               texturecube<float>   skyboxTexture   [[ texture(TFSTextureIndexSkyBox) ]]) {
    constexpr sampler linearSampler(mip_filter::linear,
                                    mag_filter::linear,
                                    min_filter::linear);
    float4 color = skyboxTexture.sample(linearSampler, in.texcoord);
    return half4(color);
}
