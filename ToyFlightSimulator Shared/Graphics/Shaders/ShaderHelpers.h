//
//  ShaderHelpers.h
//  ToyFlightSimulator
//
//  Shared inline helpers for vertex skinning, normal mapping, transparency,
//  full-screen passes, and deferred-lighting reconstruction.
//
//  Created by Albertino Padin on 8/12/26.
//

#ifndef ShaderHelpers_h
#define ShaderHelpers_h

#include <metal_stdlib>
using namespace metal;

// Linear-blend skinning: blend the joint palette into one matrix, then transform
// position/normal/tangent with it. Matrix-vector products are linear in the
// matrix, so this is mathematically identical to blending the four transformed
// vectors — at one matrix blend instead of four transforms per attribute.
// jointMatrices is never null here: animated PSOs are only ever encoded with a
// palette bound (DrawManager.SetupAnimation binds it before switching pipelines,
// and unbinds it only after restoring the non-animated PSO).
inline float4x4 BlendJointMatrix(constant float4x4 *jointMatrices, ushort4 joints, float4 weights) {
    return weights.x * jointMatrices[joints.x] +
           weights.y * jointMatrices[joints.y] +
           weights.z * jointMatrices[joints.z] +
           weights.w * jointMatrices[joints.w];
}

// Decode a [0,1]-encoded tangent-space normal-map sample and rotate it onto the
// interpolated surface basis. World-space float variant for the tiled G-buffer,
// whose T/B/N interpolants are float3 in world space. Each basis vector is
// renormalized: interpolation denormalizes them unevenly, which reweights the
// tangent-space components — a skew that normalizing only the combined result
// would keep.
inline float3 ApplyNormalMapWorld(half3 sampleRGB, float3 T, float3 B, float3 N) {
    float3 tn = normalize(float3(sampleRGB) * 2.0 - 1.0);
    return normalize(tn.x * normalize(T) + tn.y * normalize(B) + tn.z * normalize(N));
}

// Decode a [0,1]-encoded tangent-space normal-map sample and rotate it onto the
// interpolated surface basis. Eye-space half-precision variant for the
// single-pass deferred G-buffer, whose T/B/N interpolants are half3 in eye
// space. Only normal-map SAMPLES get the *2-1 decode — an interpolated
// geometric normal is already in [-1,1] and must not pass through this.
// T/B/N arrive unnormalized (the vertex stage doesn't normalize): the
// normalMatrix's uniform scale is common to all three, so it cancels in the
// final normalize; the small uneven interpolation skew the World variant
// corrects per-input is accepted on this half-precision path.
inline half3 ApplyNormalMapEye(half3 sampleRGB, half3 T, half3 B, half3 N) {
    half3 tn = normalize(sampleRGB * 2.0h - 1.0h);
    return normalize(tn.x * T + tn.y * B + tn.z * N);
}

// Combine a sampled alpha with the material's opacity: when both already agree
// the surface is translucent, keep the more opaque of the two (texture detail
// wins over a weaker material constant); otherwise the material's opacity caps
// the sampled alpha.
inline float ResolveOpacity(float sampledAlpha, float materialOpacity) {
    if (sampledAlpha < 1.0 && materialOpacity < 1.0) {
        return max(sampledAlpha, materialOpacity);
    }

    return min(sampledAlpha, materialOpacity);
}

// Base-color source cascade shared by the G-buffer and transparency fragments:
// per-instance object-color override, else the base-color texture, else the
// caller's fallback (material color or interpolated vertex color).
inline float4 ResolveBaseColor(bool useObjectColor,
                               float4 objectColor,
                               float4 fallbackColor,
                               texture2d<half> baseColorMap,
                               sampler s,
                               float2 uv) {
    if (useObjectColor)                 { return objectColor; }
    if (!is_null_texture(baseColorMap)) { return float4(baseColorMap.sample(s, uv)); }
    return fallbackColor;
}

// Same cascade for float-element textures (Base.metal and the OIT material
// fragment bind texture2d<float>) — MSL textures don't implicitly convert
// between element types, so each needs its own overload.
inline float4 ResolveBaseColor(bool useObjectColor,
                               float4 objectColor,
                               float4 fallbackColor,
                               texture2d<float> baseColorMap,
                               sampler s,
                               float2 uv) {
    if (useObjectColor)                 { return objectColor; }
    if (!is_null_texture(baseColorMap)) { return float4(baseColorMap.sample(s, uv)); }
    return fallbackColor;
}

// Recover the eye-space position of a G-buffer fragment: scale the interpolated
// view ray so its z equals the stored eye-space depth. The depth is a
// z-coordinate, not a radial distance — normalize(eyeRay) * depth lands off the
// ray and is NOT equivalent.
inline float3 ReconstructEyePosition(float3 eyeRay, float eyeSpaceDepth) {
    return eyeRay * (eyeSpaceDepth / eyeRay.z);
}


struct FullScreenVertexOut {
    float4 position [[ position ]];
    float2 uv;
};

// One triangle covering the whole screen: draw with vertexCount 3, no vertex
// buffer or vertex descriptor. uv is [0,1] in texture convention (y down;
// uv (0,0) at NDC top-left). The NDC winding is clockwise, which is
// front-facing under the engine's global setFrontFacing(.clockwise), so it
// survives back-face culling either way.
inline FullScreenVertexOut FullScreenTriangleVertex(uint vid) {
    float2 ndc = float2(vid == 1 ? 3.0 : -1.0,
                        vid == 2 ? -3.0 : 1.0);
    FullScreenVertexOut out = {
        .position = float4(ndc, 0, 1),
        .uv = float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5)
    };

    return out;
}

#endif /* ShaderHelpers_h */
