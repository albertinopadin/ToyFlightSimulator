//
//  TiledMultisampledResolve.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/24.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"

kernel void
average_resolve_tile_kernel(imageblock<FragData> imageBlockColors,
                            ushort2 tid [[ thread_position_in_threadgroup ]]) {
    const ushort pixelColorCount = imageBlockColors.get_num_colors(tid);
    half4 resolvedColor = half4(0);
    
    for (int i = 0; i < pixelColorCount; ++i) {
        const half4 color = imageBlockColors.read(tid, i, imageblock_data_rate::color).color;
        const ushort sampleColorCount = popcount(imageBlockColors.get_color_coverage_mask(tid, i));
        resolvedColor += color * sampleColorCount;
    }
    
    resolvedColor /= imageBlockColors.get_num_samples();
    
    const ushort outputSampleMask = 0xF;
    imageBlockColors.write(FragData{ resolvedColor }, tid, outputSampleMask);
}
