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

//fragment GBufferOut
//tiled_msaa_gbuffer_fragment(VertexOut                   in                  [[ stage_in ]],
//                            constant MaterialProperties &material           [[ buffer(TFSBufferIndexMaterial) ]],
//                            texture2d_ms<float>         baseColorTexture    [[ texture(TFSTextureIndexBaseColor) ]],
//                            texture2d_ms<float>         normalTexture       [[ texture(TFSTextureIndexNormal) ]],
//                            depth2d_ms<float>           shadowTexture       [[ texture(TFSTextureIndexShadow) ]]) {
//    float4 color = 0;
//    
//    int xCoord = floor(in.uv.x * baseColorTexture.get_width());
//    int yCoord = floor(in.uv.y * baseColorTexture.get_height());
//    uint2 coords = uint2(xCoord, yCoord);
//    
//    if (in.useObjectColor) {
//        color = in.objectColor;
//    } else if (!is_null_texture(baseColorTexture)) {
//        uint numSamples = baseColorTexture.get_num_samples();
//        
//        for (uint i = 0; i < numSamples; ++i) {
//            color += baseColorTexture.read(coords, i);
//        }
//        
//        color /= numSamples;
//    }
//    
//    color.a = Lighting::CalculateShadowMSAA(in.shadowPosition, shadowTexture);
//    
//    float4 normal = float4(normalize(in.worldNormal), 1.0);
//    
//    if (!in.useObjectColor && !is_null_texture(normalTexture)) {
//        uint numSamples = normalTexture.get_num_samples();
//        
//        for (uint i = 0; i < numSamples; ++i) {
//            normal += normalTexture.read(coords, i);
//        }
//        
//        normal /= numSamples;
//    }
//    
//    GBufferOut out {
//        .albedo = color,
//        .normal = normal,
//        .position = float4(in.worldPosition, 1.0)
//    };
//    return out;
//}

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
