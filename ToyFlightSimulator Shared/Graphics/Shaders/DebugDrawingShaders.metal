//
//  DebugDrawingShaders.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/30/22.
//

#include <metal_stdlib>
#include "Lighting.metal"
#include "Shared.metal"

using namespace metal;

fragment half4 debug_fragment_shader(RasterizerData rd [[ stage_in ]]) {
    return half4(rd.color);
}
