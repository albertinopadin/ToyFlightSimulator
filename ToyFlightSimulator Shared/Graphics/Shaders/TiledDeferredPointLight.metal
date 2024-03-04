//
//  TiledDeferredPointLight.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/3/24.
//

#include <metal_stdlib>
using namespace metal;

vertex float4 tiled_deferred_point_light_vertex() {
    return float4(1, 1, 1, 1);
}

fragment float4 tiled_deferred_point_light_fragment() {
    return float4(1, 1, 1, 1);
}
