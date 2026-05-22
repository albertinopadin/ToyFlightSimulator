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
tiled_msaa_gbuffer_fragment(VertexOut                          in                  [[ stage_in ]],
                            constant SceneConstants            &sceneConstants     [[ buffer(TFSBufferIndexSceneConstants) ]],
                            constant MaterialProperties        &material           [[ buffer(TFSBufferIndexMaterial) ]],
                            constant MaterialTextureTransforms &uvXforms           [[ buffer(TFSBufferIndexMaterialTextureTransforms) ]],
                            constant LightData                 &lightData          [[ buffer(TFSBufferDirectionalLightData) ]],
                            sampler                            sampler2d           [[ sampler(0) ]],
                            texture2d<half>                    baseColorTexture    [[ texture(TFSTextureIndexBaseColor) ]],
                            texture2d<half>                    normalTexture       [[ texture(TFSTextureIndexNormal) ]],
                            // The MSAA shadow generation pass resolves into a non-MSAA texture2DArray;
                            // the fragment shader samples the (already-resolved) cascade array.
                            depth2d_array<float>               shadowArray         [[ texture(TFSTextureIndexShadow) ]]) {
    float2 baseUV   = in.uv;
    float2 normalUV = in.uv;
    if (uvXforms.hasTextureTransforms) {
        baseUV   = ApplyUVTransform(in.uv, uvXforms.baseColorUVTransform);
        normalUV = ApplyUVTransform(in.uv, uvXforms.normalUVTransform);
    }

    float4 color = material.color;

    if (in.useObjectColor) {
        color = in.objectColor;
    } else if (!is_null_texture(baseColorTexture)) {
        color = float4(baseColorTexture.sample(sampler2d, baseUV));
    }

    // Per-fragment world-space distance — see TiledDeferredGBuffer.metal
    // (sibling fragment shader) and debugging/claude/csm_select_cascade_drift.md.
    float fragViewSpaceDepth = distance(in.worldPosition, sceneConstants.cameraPosition);

    color.a = Lighting::CalculateShadowMSAA(in.worldPosition,
                                            fragViewSpaceDepth,
                                            in.worldNormal,
                                            lightData,
                                            shadowArray);

    float4 normal = float4(normalize(in.worldNormal), 1.0);

    if (!in.useObjectColor && !is_null_texture(normalTexture)) {
        normal = float4(normalTexture.sample(sampler2d, normalUV));
    }
    
    GBufferOut out {
        .albedo = color,
        .normal = normal,
        .position = float4(in.worldPosition, 1.0)
    };
    return out;
}
