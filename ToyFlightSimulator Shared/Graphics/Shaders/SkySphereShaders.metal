//
//  SkySphereShaders.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

#include <metal_stdlib>
using namespace metal;

#import "TFSCommon.h"
#import "ShaderDefinitions.h"

vertex RasterizerData skysphere_vertex(const    VertexIn        vIn             [[ stage_in ]],
                                       constant SceneConstants &sceneConstants  [[ buffer(TFSBufferIndexSceneConstants) ]],
                                       constant ModelConstants &modelConstants  [[ buffer(TFSBufferModelConstants) ]]) {
    float4 worldPosition = modelConstants.modelMatrix * float4(vIn.position, 1);
    
    RasterizerData rd = {
        .position = sceneConstants.projectionMatrix * sceneConstants.skyViewMatrix * worldPosition,
        .textureCoordinate = vIn.textureCoordinate,
        .totalGameTime = sceneConstants.totalGameTime
    };
    
    return rd;
}

fragment half4 skysphere_fragment(RasterizerData rd [[ stage_in ]],
                                  sampler sampler2d [[ sampler(0) ]],
                                  texture2d<float> skySphereTexture [[ texture(10) ]]) {
    float2 texCoord = rd.textureCoordinate;
    float4 color = skySphereTexture.sample(sampler2d, texCoord, level(0));
    return half4(color);
}
