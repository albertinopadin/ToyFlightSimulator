//
//  TiledMSAAGBuffer.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/24.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"
#import "Lighting.metal"

fragment GBufferOut
tiled_msaa_gbuffer_fragment(VertexOut                   in                  [[ stage_in ]],
                            constant MaterialProperties &material           [[ buffer(TFSBufferIndexMaterial) ]],
                            sampler                     sampler2d           [[ sampler(0) ]],
                            texture2d<half>             baseColorTexture    [[ texture(TFSTextureIndexBaseColor) ]],
                            texture2d<half>             normalTexture       [[ texture(TFSTextureIndexNormal) ]],
                            depth2d_ms<float>           shadowTexture       [[ texture(TFSTextureIndexShadow) ]]) {
    float4 color;
    
    if (in.useObjectColor) {
        color = in.objectColor;
    } else if (!is_null_texture(baseColorTexture)) {
        color = float4(baseColorTexture.sample(sampler2d, in.uv));
    }
    
    color.a = Lighting::CalculateShadowMSAA(in.shadowPosition, shadowTexture);
    
    float4 normal = float4(normalize(in.worldNormal), 1.0);
    
    if (!in.useObjectColor && !is_null_texture(normalTexture)) {
        normal = float4(normalTexture.sample(sampler2d, in.uv));
    }
    
    GBufferOut out {
        .albedo = color,
        .normal = normal,
        .position = float4(in.worldPosition, 1.0)
    };
    return out;
}
