//
//  FinalShaders.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"

struct FinalRasterizerData {
    float4 position [[ position ]];
    float2 textureCoordinate;
};

vertex FinalRasterizerData final_vertex(const VertexIn vIn [[ stage_in ]]) {
    FinalRasterizerData rd = {
        .position = float4(vIn.position, 1.0),
        .textureCoordinate = float2(vIn.textureCoordinate)
    };
    
    return rd;
}

fragment half4 final_fragment(const FinalRasterizerData rd [[ stage_in ]],
                              texture2d<float> baseTexture [[ texture(0) ]]) {
    sampler s;
    float2 textureCoordinate = rd.textureCoordinate;
    textureCoordinate.y = 1 - textureCoordinate.y;  // Flip
    float4 color = baseTexture.sample(s, textureCoordinate);
    
    return half4(color);
}
