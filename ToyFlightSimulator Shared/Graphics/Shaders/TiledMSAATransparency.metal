//
//  TiledMSAATransparency.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/24.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"
#import "ShaderHelpers.h"

fragment float4
tiled_msaa_transparency_fragment(VertexOut                          in                  [[ stage_in ]],
                                 constant MaterialProperties        &material           [[ buffer(TFSBufferIndexMaterial) ]],
                                 constant MaterialTextureTransforms &uvXforms           [[ buffer(TFSBufferIndexMaterialTextureTransforms) ]],
                                 sampler                            sampler2d           [[ sampler(0) ]],
                                 texture2d_ms<float>                baseColorTexture    [[ texture(TFSTextureIndexBaseColor) ]]) {
    float2 baseUV = in.uv;
    if (uvXforms.hasTextureTransforms) {
        baseUV = ApplyUVTransform(in.uv, uvXforms.baseColorUVTransform);
    }

    float4 color = material.color;

    if (in.useObjectColor) {
        color = in.objectColor;
    } else if (!is_null_texture(baseColorTexture)) {
        int xCoord = floor(baseUV.x * baseColorTexture.get_width());
        int yCoord = floor(baseUV.y * baseColorTexture.get_height());
        uint2 coords = uint2(xCoord, yCoord);

        uint numSamples = baseColorTexture.get_num_samples();

        for (uint i = 0; i < numSamples; ++i) {
            color += baseColorTexture.read(coords, i);
        }

        color /= numSamples;
    }
    
    color.a = ResolveOpacity(color.a, material.opacity);
    
    return color;
}
