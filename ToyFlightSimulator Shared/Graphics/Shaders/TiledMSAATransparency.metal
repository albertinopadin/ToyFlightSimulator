//
//  TiledMSAATransparency.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/24.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"

fragment float4
tiled_msaa_transparency_fragment(VertexOut                   in                  [[ stage_in ]],
                                 constant MaterialProperties &material           [[ buffer(TFSBufferIndexMaterial) ]],
                                 sampler                     sampler2d           [[ sampler(0) ]],
                                 texture2d_ms<float>         baseColorTexture    [[ texture(TFSTextureIndexBaseColor) ]]) {
    float4 color = material.color;
    
    if (in.useObjectColor) {
        color = in.objectColor;
    } else if (!is_null_texture(baseColorTexture)) {
        int xCoord = floor(in.uv.x * baseColorTexture.get_width());
        int yCoord = floor(in.uv.y * baseColorTexture.get_height());
        uint2 coords = uint2(xCoord, yCoord);
        
        uint numSamples = baseColorTexture.get_num_samples();
        
        for (uint i = 0; i < numSamples; ++i) {
            color += baseColorTexture.read(coords, i);
        }
        
        color /= numSamples;
    }
    
    if (color.a < 1.0 && material.opacity < 1.0) {
        color.a = max(color.a, material.opacity);
    } else {
        color.a = min(color.a, material.opacity);
    }
    
    return color;
}
