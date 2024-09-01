//
//  LightManager.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

import MetalKit

final class LightManager {
    private static var _lightObjects: [LightObject] = []
    
    public static func AddLightObject(_ lightObject: LightObject) {
        Self._lightObjects.append(lightObject)
    }
    
    public static func GetLightObjects(lightType: LightType) -> [LightObject] {
        return Self._lightObjects.filter { $0.lightType == lightType }
    }
    
    public static func RemoveAllLights() {
        Self._lightObjects.removeAll()
    }

    public static func GetDirectionalLightData(viewMatrix: float4x4) -> [LightData] {
        let lightObjs = Self.GetLightObjects(lightType: Directional)
        lightObjs.forEach { $0.lightData.lightEyeDirection = normalize(viewMatrix * float4(-$0.getPosition(), 1)).xyz }
        return lightObjs.map { $0.lightData }
    }
    
    public static func GetPointLightData() -> [LightData] {
        return Self.GetLightObjects(lightType: Point).map { $0.lightData }
    }
    
    public static func SetDirectionalLightData(_ renderEncoder: MTLRenderCommandEncoder,
                                               cameraPosition: float3,
                                               viewMatrix: float4x4) {
        var lightData = Self.GetDirectionalLightData(viewMatrix: viewMatrix)
        var lightCount = lightData.count
        renderEncoder.setFragmentBytes(&lightCount, 
                                       length: Int32.size,
                                       index: TFSBufferDirectionalLightsNum.index)
        renderEncoder.setFragmentBytes(&lightData,
                                       length: LightData.stride(lightCount),
                                       index: TFSBufferDirectionalLightData.index)
    }
    
    public static func SetPointLightData(_ renderEncoder: MTLRenderCommandEncoder) {
        var pointLightData = Self.GetPointLightData()
        
        renderEncoder.setVertexBytes(&pointLightData,
                                     length: LightData.stride(pointLightData.count),
                                     index: TFSBufferPointLightsData.index)
        
        renderEncoder.setFragmentBytes(&pointLightData,
                                       length: LightData.stride(pointLightData.count),
                                       index: TFSBufferPointLightsData.index)
    }
}
