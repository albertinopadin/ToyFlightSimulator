//
//  Composition.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/24.
//

#include <metal_stdlib>
using namespace metal;

/// The normalized device coordinates (NDC) for two triangles that form a full-screen quad.
constant float2 quadVertices[] = {
    float2(-1, -1),
    float2(-1,  1),
    float2( 1,  1),
    float2(-1, -1),
    float2( 1,  1),
    float2( 1, -1)
};

/// A vertex format for drawing a full-screen quad.
struct CompositionVertexOut {
    float4 position [[position]];
    float2 uv;
};

/// Outputs the normalized device coordinates (NDC) to render a full-screen quad based on the vertex ID.
vertex CompositionVertexOut
compositeVertexShader(unsigned short vid [[vertex_id]])
{
    const float2 position = quadVertices[vid];
    
    CompositionVertexOut out;
    
    out.position = float4(position, 0, 1);
    out.position.y *= -1;
    out.uv = position * 0.5f + 0.5f;
    
    return out;
}

/// Copies the input resolve texture to the output.
fragment half4
compositeFragmentShader(CompositionVertexOut in [[stage_in]],
                        texture2d<half> resolvedTexture)
{
    constexpr sampler sam(min_filter::nearest, mag_filter::nearest, mip_filter::none);
    
    const half3 color = resolvedTexture.sample(sam, in.uv).xyz;
    
    return half4(color, 1.0f);
}
