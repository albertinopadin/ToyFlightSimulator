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
