//
//  TileDeferredGBuffer.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/2/24.
//

#include <metal_stdlib>
using namespace metal;


vertex float4 tiled_deferred_gbuffer_vertex() {
    return float4(1, 1, 1, 1);
}


fragment float4 tiled_deferred_gbuffer_fragment() {
    return float4(0, 0, 1, 1);
}

