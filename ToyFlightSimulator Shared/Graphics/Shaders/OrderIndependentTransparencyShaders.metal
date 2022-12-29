//
//  OrderIndependentTransparencyShaders.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 12/27/22.
//

#include <metal_stdlib>
#include "Lighting.metal"
#include "Shared.metal"

using namespace metal;

static constexpr constant short kNumLayers = 4;

struct TransparentFragmentValues {
    rgba8unorm<half4> colors [[ raster_order_group(0) ]] [kNumLayers];
    half depths [[ raster_order_group(0) ]] [kNumLayers];
};

struct TransparentFragmentStore {
    TransparentFragmentValues values [[ imageblock_data ]];
};

kernel void init_transparent_fragment_store(imageblock<TransparentFragmentValues, imageblock_layout_explicit> blockData,
                                            ushort2 localThreadID [[ thread_position_in_threadgroup ]]) {
    threadgroup_imageblock TransparentFragmentValues* fragmentValues = blockData.data(localThreadID);
    for (short i = 0; i < kNumLayers; ++i) {
        fragmentValues->colors[i] = half4(0.0h);
        fragmentValues->depths[i] = half(INFINITY);
    }
}

fragment TransparentFragmentStore transparent_fragment_shader(RasterizerData rd [[ stage_in ]],
                                                              TransparentFragmentValues fragmentValues [[ imageblock_data ]]) {
    TransparentFragmentStore out;
    half4 finalColor = half4(rd.color);
    finalColor.xyz *= finalColor.w;
    
    // Get fragment distance from camera:
//    half depth = rd.position.z / rd.position.w;  // What to do about w? position is only a float3
    half depth = rd.position.z;
    
    for (short i = 0; i < kNumLayers; ++i) {
        half layerDepth = fragmentValues.depths[i];
        half4 layerColor = fragmentValues.colors[i];
        
        bool insert (depth <= layerDepth);
        fragmentValues.colors[i] = insert ? finalColor : layerColor;
        fragmentValues.depths[i] = insert ? depth : layerDepth;
        
        finalColor = insert ? layerColor : finalColor;
        depth = insert ? layerDepth : depth;
    }
    
    out.values = fragmentValues;
    return out;
}

fragment half4 blend_fragments(TransparentFragmentValues fragmentValues [[ imageblock_data ]],
                               half4 forwardOpaqueColor [[ color(0), raster_order_group(0) ]]) {
    half4 out;
    
    out.xyz = forwardOpaqueColor.xyz;
    
    for (short i = kNumLayers - 1; i >= 0; --i) {
        half4 layerColor = fragmentValues.colors[i];
        out.xyz = layerColor.xyz + (1.0h - layerColor.w) * out.xyz;
    }
    
    out.w = 1.0;
    return out;
}
