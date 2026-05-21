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

// `cascadeVP` is a per-pass push constant: the view-projection matrix of the
// cascade this draw call is rendering into. The host (ShadowRendering.swift's
// encodeShadowMapPass) iterates over cascades and pushes the appropriate
// matrix at TFSBufferIndexShadowCascadeVP. Decoupling the matrix from
// LightData lets this shader stay cascade-count agnostic.
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

    if (jointMatrices != nullptr) {
        float4 weights = in.jointWeights;
        ushort4 joints = in.joints;

        position = weights.x * (jointMatrices[joints.x] * position) +
                weights.y * (jointMatrices[joints.y] * position) +
                weights.z * (jointMatrices[joints.z] * position) +
                weights.w * (jointMatrices[joints.w] * position);
    }

    ShadowOutput out = {
        .position = cascadeVP * modelInstance.modelMatrix * position
    };

    return out;
}
