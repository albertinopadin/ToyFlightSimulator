//
//  Composition.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/30/24.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderHelpers.h"

/// THE full-screen vertex stage (E6): every generic full-screen PSO binds this
/// one function — composite, tiled directional light, OIT blend, OIT final.
/// A pass needing extra varyings (the single-pass directional light's eye ray)
/// builds its own vertex on FullScreenTriangleVertex instead.
vertex FullScreenVertexOut full_screen_vertex(uint vid [[ vertex_id ]]) {
    return FullScreenTriangleVertex(vid);
}

/// Copies the input resolve texture to the output.
fragment half4 compositeFragmentShader(FullScreenVertexOut in [[stage_in]], texture2d<half> resolvedTexture) {
    constexpr sampler sam(min_filter::nearest, mag_filter::nearest, mip_filter::none);
    const half3 color = resolvedTexture.sample(sam, in.uv).xyz;
    return half4(color, 1.0f);
}
