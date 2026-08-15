//
//  TiledMSAAGBuffer.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/24.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"
#import "ShaderHelpers.h"
#import "Lighting.metal"

fragment GBufferOut
tiled_msaa_gbuffer_fragment(
VertexOut                          in                  [[ stage_in ]],
constant SceneConstants            &sceneConstants     [[ buffer(TFSBufferIndexSceneConstants) ]],
constant MaterialProperties        &material           [[ buffer(TFSBufferIndexMaterial) ]],
constant MaterialTextureTransforms &uvXforms           [[buffer(TFSBufferIndexMaterialTextureTransforms) ]],
constant LightData                 &lightData          [[ buffer(TFSBufferDirectionalLightData) ]],
sampler                            sampler2d           [[ sampler(0) ]],
texture2d<half>                    baseColorTexture    [[ texture(TFSTextureIndexBaseColor) ]],
texture2d<half>                    normalTexture       [[ texture(TFSTextureIndexNormal) ]],
depth2d_array<float>               shadowArray         [[ texture(TFSTextureIndexShadow) ]]) {
    float2 baseUV   = in.uv;
    float2 normalUV = in.uv;
    if (uvXforms.hasTextureTransforms) {
        baseUV   = ApplyUVTransform(in.uv, uvXforms.baseColorUVTransform);
        normalUV = ApplyUVTransform(in.uv, uvXforms.normalUVTransform);
    }
    
    float4 color = ResolveBaseColor(in.useObjectColor,
                                    in.objectColor,
                                    material.color,
                                    baseColorTexture,
                                    sampler2d,
                                    baseUV);

    float fragViewSpaceDepth = distance(in.worldPosition, sceneConstants.cameraPosition);
    color.a = Lighting::CalculateShadow(in.worldPosition,
                                        fragViewSpaceDepth,
                                        in.worldNormal,
                                        lightData,
                                        shadowArray);

    float3 N = normalize(in.worldNormal);
    if (!in.useObjectColor && !is_null_texture(normalTexture)) {
        half3 tangentSample = normalTexture.sample(sampler2d, normalUV).xyz;
        N = ApplyNormalMapWorld(tangentSample, in.worldTangent, in.worldBitangent, in.worldNormal);
    }
    
    float4 normal = float4(N, 1.0);
    
    GBufferOut out {
        .albedo = color,
        .normal = normal,
        .position = float4(in.worldPosition, 1.0)
    };
    return out;
}
