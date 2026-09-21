//
//  Base.metal
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/25/22.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderDefinitions.h"
#import "ShaderHelpers.h"
#import "Lighting.metal"

struct FragmentOutput {
    half4 color0 [[ color(0) ]];
    half4 color1 [[ color(1) ]];
};

vertex RasterizerData base_vertex(const VertexIn vIn [[ stage_in ]],
                                  constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                  constant ModelConstants *modelConstants [[ buffer(TFSBufferModelConstants) ]],
                                  uint instanceId [[ instance_id ]]) {
    ModelConstants modelInstance = modelConstants[instanceId];
    float4 worldPosition = modelInstance.modelMatrix * float4(vIn.position, 1);
    
    RasterizerData rd = {
        // Order of matrix multiplication is important here:
        .position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition,
        .color = vIn.color,
        .objectColor = modelInstance.objectColor,
        .textureCoordinate = vIn.textureCoordinate,
        .totalGameTime = sceneConstants.totalGameTime,
        .worldPosition = worldPosition.xyz,
        .toCameraVector = sceneConstants.cameraPosition - worldPosition.xyz,
        // Direction vectors go through the 3x3 normalMatrix: a modelMatrix
        // multiply with w = 1 would add the model translation and then
        // normalize across all four components. They are left unnormalized
        // here — interpolation denormalizes anyway, so the fragments
        // renormalize once.
        .surfaceNormal = modelInstance.normalMatrix * vIn.normal,
        .surfaceTangent = modelInstance.normalMatrix * vIn.tangent,
        .surfaceBitangent = modelInstance.normalMatrix * vIn.bitangent,
        .instanceId = instanceId,
        .useObjectColor = modelInstance.useObjectColor
    };

    return rd;
}

vertex RasterizerData base_animated_vertex(const VertexIn vIn [[ stage_in ]],
                                           constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                           constant ModelConstants *modelConstants [[ buffer(TFSBufferModelConstants) ]],
                                           constant float4x4 *jointMatrices [[ buffer(TFSBufferIndexJointBuffer) ]],
                                           uint instanceId [[ instance_id ]]) {
    ModelConstants modelInstance = modelConstants[instanceId];
    // w = 1 for the position (translation applies), w = 0 for the three directions
    // (translation ignored). All four go through the SAME blended joint matrix: a
    // normal-map sample decodes as x*T + y*B + z*N, so T and B must follow the pose
    // exactly as N does or the bump tilts by the joint rotation (secondary item 5 in
    // the shading doc; the tiled and single-pass animated vertices already do this).
    float4 position = float4(vIn.position, 1);
    float4 normal = float4(vIn.normal, 0);
    float4 tangent = float4(vIn.tangent, 0);
    float4 bitangent = float4(vIn.bitangent, 0);
    
    float4x4 skinMatrix = BlendJointMatrix(jointMatrices, vIn.joints, vIn.jointWeights);
    position = skinMatrix * position;
    normal = skinMatrix * normal;
    tangent = skinMatrix * tangent;
    bitangent = skinMatrix * bitangent;

    float4 worldPosition = modelInstance.modelMatrix * position;

    RasterizerData rd = {
        // Order of matrix multiplication is important here:
        .position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition,
        .color = vIn.color,
        .objectColor = modelInstance.objectColor,
        .textureCoordinate = vIn.textureCoordinate,
        .totalGameTime = sceneConstants.totalGameTime,
        .worldPosition = worldPosition.xyz,
        .toCameraVector = sceneConstants.cameraPosition - worldPosition.xyz,
        .surfaceNormal = modelInstance.normalMatrix * normal.xyz,
        .surfaceTangent = modelInstance.normalMatrix * tangent.xyz,
        .surfaceBitangent = modelInstance.normalMatrix * bitangent.xyz,
        .instanceId = instanceId,
        .useObjectColor = modelInstance.useObjectColor
    };

    return rd;
}

fragment FragmentOutput base_fragment(RasterizerData rd [[ stage_in ]]) {
    float4 color = rd.color;
    float3 unitNormal = normalize(rd.surfaceNormal);
    
    FragmentOutput out = {
        .color0 = half4(color.r, color.g, color.b, color.a),
        .color1 = half4(unitNormal.x, unitNormal.y, unitNormal.z, 1.0)
    };
    
    return out;
}


fragment FragmentOutput
material_fragment(          RasterizerData            rd              [[ stage_in ]],
                  constant  MaterialProperties        &material       [[ buffer(TFSBufferIndexMaterial) ]],
                  constant  MaterialTextureTransforms &uvXforms       [[ buffer(TFSBufferIndexMaterialTextureTransforms) ]],
                  constant  int                       &lightCount     [[ buffer(TFSBufferDirectionalLightsNum) ]],
                  constant  LightData                 *lightData      [[ buffer(TFSBufferDirectionalLightData) ]],
                            sampler                   sampler2d       [[ sampler(0) ]],
                            texture2d<float>          baseColorMap    [[ texture(TFSTextureIndexBaseColor) ]],
                            texture2d<float>          normalMap       [[ texture(TFSTextureIndexNormal) ]]) {
    // Per-slot UV transforms (glTF KHR_texture_transform): each texture has its own matrix,
    // identity for slots without one, so both UVs start from the raw coordinate and the
    // normal map is sampled with ITS transform, as in every deferred G-buffer fragment.
    float2 baseUV = rd.textureCoordinate;
    float2 normalUV = rd.textureCoordinate;
    if (uvXforms.hasTextureTransforms) {
        baseUV = ApplyUVTransform(rd.textureCoordinate, uvXforms.baseColorUVTransform);
        normalUV = ApplyUVTransform(rd.textureCoordinate, uvXforms.normalUVTransform);
    }
    
    float4 baseColor = ResolveBaseColor(rd.useObjectColor,
                                        rd.objectColor,
                                        material.color,
                                        baseColorMap,
                                        sampler2d,
                                        baseUV);
    
    // World-space unit normal: the interpolated geometric normal, or the normal-map sample
    // rotated onto the interpolated T/B/N basis with the helper the tiled G-buffer uses, so
    // every renderer shares one normal-map path and one handedness convention. color1
    // carries this normal whether or not the surface is lit.
    float3 unitNormal = normalize(rd.surfaceNormal);
    
    if (!is_null_texture(normalMap) && !rd.useObjectColor) {
        float3 normalSample = normalMap.sample(sampler2d, normalUV).rgb;
        unitNormal = ApplyNormalMapWorld(normalSample, rd.surfaceTangent, rd.surfaceBitangent, rd.surfaceNormal);
    }
    
    // Forward Blinn-Phong through the shared function: ambient + litFraction * (diffuse
    // + specular), the same math the deferred sun passes use, so the renderers agree.
    //
    // The lightCount guard does two jobs. LightManager.SetDirectionalLightData binds the
    // LightData array only when at least one directional light exists, so with none the
    // pointer refers to an unbound slot and must not be read. And ambient lives inside the
    // per-light call, so a sunless scene would otherwise sum zero lights and draw black;
    // the guard draws the base color unlit instead.
    float3 litColor;
    if (lightCount == 0 || !material.isLit) {
        litColor = baseColor.rgb;
    } else {
        float3 toCamera = normalize(rd.toCameraVector);
        litColor = 0;
        for (int i = 0; i < lightCount; i++) {
            constant LightData &light = lightData[i];
            // Only directional lights are bound at this index today (LightManager keeps
            // point lights in a separate list), so the point-light branch is reserved for
            // when they are: direction only, no attenuation yet.
            float3 toLight;
            if (light.type == Directional) {
                toLight = light.direction;
            } else {
                toLight = normalize(light.position - rd.worldPosition);
            }
            
            // The forward path has no shadow map, so litFraction is 1 (fully lit).
            // Landing-order step 1: specular off. Step 6 switches DEFAULT_SPECULAR_STRENGTH
            // to material.specular.r once the material defaults become 0.25 / shininess 32;
            // today's defaults (1.0 / 2) would add a white N.H^2 lobe to every lit surface.
            // Known limitation: each light adds its own ambient term, so with more than one
            // directional light the ambient is counted more than once.
            litColor += Lighting::ShadeDirectionalBlinnPhong(baseColor.rgb,
                                                             unitNormal,
                                                             toLight,
                                                             toCamera,
                                                             light,
                                                             Lighting::DEFAULT_SPECULAR_STRENGTH,
                                                             material.shininess,
                                                             1.0);
        }
    }
    
    FragmentOutput out = {
        .color0 = half4(half3(litColor), baseColor.a),
        .color1 = half4(half3(unitNormal), 1.0)
    };
    
    return out;
}
