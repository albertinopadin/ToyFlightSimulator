//
//  ShadowShaders.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/21/23.
//

#include <metal_stdlib>
#include "TFSShaderTypes.h"
#include "Shared.metal"
using namespace metal;

struct ShadowOutput
{
    float4 position [[ position ]];
};

vertex ShadowOutput shadow_vertex(const VertexIn in [[ stage_in ]],
                                  constant LightData &lightData [[ buffer(TFSBufferDirectionalLightData) ]],
                                  constant ModelConstants &modelConstants [[ buffer(TFSBufferModelConstants) ]])
{
    ShadowOutput out;
    out.position = lightData.shadowViewProjectionMatrix * modelConstants.modelMatrix * float4(in.position, 1.0);
    return out;
}
