//
//  Shadow.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/21/23.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"

struct ShadowOutput
{
    float4 position [[ position ]];
};

vertex ShadowOutput shadow_vertex(const     VertexIn        in              [[ stage_in ]],
                                  constant  LightData       &lightData      [[ buffer(TFSBufferDirectionalLightData) ]],
                                  constant  ModelConstants  *modelConstants [[ buffer(TFSBufferModelConstants) ]],
                                            uint            instanceId      [[ instance_id ]])
{
    ModelConstants modelInstance = modelConstants[instanceId];
    ShadowOutput out = {
        .position = lightData.shadowViewProjectionMatrix * modelInstance.modelMatrix * float4(in.position, 1.0)
    };
    
    return out;
}



vertex ShadowOutput shadow_animated_vertex(
  const     VertexIn        in              [[ stage_in ]],
  constant  LightData       &lightData      [[ buffer(TFSBufferDirectionalLightData) ]],
  constant  ModelConstants  *modelConstants [[ buffer(TFSBufferModelConstants) ]],
  constant  float4x4        *jointMatrices  [[ buffer(TFSBufferIndexJointBuffer) ]],
            uint            instanceId      [[ instance_id ]])
{
    ModelConstants modelInstance = modelConstants[instanceId];
    float4 position = float4(in.position, 1.0);
    
    // Hope this works, ugh...
    if (jointMatrices != nullptr) {
        float4 weights = in.jointWeights;
        ushort4 joints = in.joints;
        
        position = weights.x * (jointMatrices[joints.x] * position) +
                weights.y * (jointMatrices[joints.y] * position) +
                weights.z * (jointMatrices[joints.z] * position) +
                weights.w * (jointMatrices[joints.w] * position);
    }
    
    ShadowOutput out = {
        .position = lightData.shadowViewProjectionMatrix * modelInstance.modelMatrix * position
    };
    
    return out;
}
