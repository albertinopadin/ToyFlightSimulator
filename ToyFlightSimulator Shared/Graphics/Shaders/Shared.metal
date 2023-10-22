//
//  Shared.metal
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/25/22.
//

#ifndef SHARED_METAL
#define SHARED_METAL

#include <metal_stdlib>
#include "TFSShaderTypes.h"

using namespace metal;

struct VertexIn {
    float3 position [[ attribute(TFSVertexAttributePosition) ]];
    float4 color [[ attribute(TFSVertexAttributeColor) ]];
    float2 textureCoordinate [[ attribute(TFSVertexAttributeTexcoord) ]];
    float3 normal [[ attribute(TFSVertexAttributeNormal) ]];
    float3 tangent [[ attribute(TFSVertexAttributeTangent) ]];
    float3 bitangent [[ attribute(TFSVertexAttributeBitangent) ]];
};

//struct VertexIn {
//    float3 normal [[ attribute(TFSVertexAttributeNormal) ]];
//    float2 textureCoordinate [[ attribute(TFSVertexAttributeTexcoord) ]];
//    float3 position [[ attribute(TFSVertexAttributePosition) ]];
//    float4 color [[ attribute(TFSVertexAttributeColor) ]];
//    float3 tangent [[ attribute(TFSVertexAttributeTangent) ]];
//    float3 bitangent [[ attribute(TFSVertexAttributeBitangent) ]];
//};

struct RasterizerData {
    float4 position [[ position ]];
    float4 color;
    float2 textureCoordinate;
    float totalGameTime;
    
    float3 worldPosition;  // To get vector to light
    float3 toCameraVector;

    float3 surfaceNormal;
    float3 surfaceTangent;
    float3 surfaceBitangent;
};

struct ModelConstants {
    float4x4 modelMatrix;
    float3x3 normalMatrix;
};

struct SceneConstants {
    float totalGameTime;
    float4x4 viewMatrix;
    float4x4 skyViewMatrix;
    float4x4 projectionMatrix;
    float4x4 projectionMatrixInverse;
    float3 cameraPosition;
};

struct Material {
    float4 color;
    bool useMaterialColor;
    bool isLit;
    
    bool useBaseTexture;
    bool useNormalMapTexture;
    bool useSpecularTexture;
    
    float3 ambient;
    float3 diffuse;
    float3 specular;
    float shininess;
};

enum LightType: uint {
    LightTypeAmbient,
    LightTypeDirectional,
    LightTypeOmni,
    LightTypePoint
};

struct LightData {
    LightType type;
    float4x4 viewProjectionMatrix;
    float4x4 shadowViewProjectionMatrix;
    float4x4 shadowTransformMatrix;
    float4 eyeDirection;
    
    float3 position;
    float3 color;
    float brightness;
    
    float ambientIntensity;
    float diffuseIntensity;
    float specularIntensity;
};

#endif
