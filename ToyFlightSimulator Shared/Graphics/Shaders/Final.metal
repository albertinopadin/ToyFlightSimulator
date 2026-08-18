//
//  Final.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"
#import "ShaderHelpers.h"

fragment half4 final_fragment(const FullScreenVertexOut in [[ stage_in ]],
                              texture2d<float> baseTexture [[ texture(0) ]]) {
    sampler s;
    // FullScreenVertexOut.uv is texture-oriented (uv (0,0) = NDC top-left =
    // texel (0,0) of the render target), so no y flip before sampling.
    float4 color = baseTexture.sample(s, in.uv);
    return half4(color);
}
