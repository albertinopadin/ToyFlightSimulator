//
//  Shadow.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/21/23.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"
#import "ShaderHelpers.h"

struct ShadowOutput
{
    float4 position [[ position ]];
};

vertex ShadowOutput shadow_vertex(const     VertexIn        in              [[ stage_in ]],
                                  constant  float4x4        &cascadeVP      [[ buffer(TFSBufferIndexShadowCascadeVP) ]],
                                  constant  ModelConstants  *modelConstants [[ buffer(TFSBufferModelConstants) ]],
                                            uint            instanceId      [[ instance_id ]])
{
    ModelConstants modelInstance = modelConstants[instanceId];
    ShadowOutput out = {
        .position = cascadeVP * modelInstance.modelMatrix * float4(in.position, 1.0)
    };

    return out;
}



vertex ShadowOutput shadow_animated_vertex(
  const     VertexIn        in              [[ stage_in ]],
  constant  float4x4        &cascadeVP      [[ buffer(TFSBufferIndexShadowCascadeVP) ]],
  constant  ModelConstants  *modelConstants [[ buffer(TFSBufferModelConstants) ]],
  constant  float4x4        *jointMatrices  [[ buffer(TFSBufferIndexJointBuffer) ]],
            uint            instanceId      [[ instance_id ]])
{
    ModelConstants modelInstance = modelConstants[instanceId];
    float4 position = float4(in.position, 1.0);
    
    position = BlendJointMatrix(jointMatrices, in.joints, in.jointWeights) * position;
    
    ShadowOutput out = {
        .position = cascadeVP * modelInstance.modelMatrix * position
    };

    return out;
}
