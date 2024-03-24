//
//  LightManager.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

import MetalKit

struct LightManager {
    private static var _lightObjects: [LightObject] = []
    
    public static func addLightObject(_ lightObject: LightObject) {
        Self._lightObjects.append(lightObject)
    }
    
    public static func getLightObjects(lightType: LightType) -> [LightObject] {
        return Self._lightObjects.filter { $0.lightType == lightType }
    }

    public static func getDirectionalLightData(viewMatrix: float4x4) -> [LightData] {
        let lightObjs = Self.getLightObjects(lightType: Directional)
        lightObjs.forEach { $0.lightData.lightEyeDirection = normalize(viewMatrix * float4(-$0.getPosition(), 1)).xyz }
        return lightObjs.map { $0.lightData }
    }
    
    public static func getPointLightData() -> [LightData] {
        return Self.getLightObjects(lightType: Point).map { $0.lightData }
    }
    
    public static func setDirectionalLightData(_ renderCommandEncoder: MTLRenderCommandEncoder,
                                               cameraPosition: float3,
                                               viewMatrix: float4x4) {
        var lightData = Self.getDirectionalLightData(viewMatrix: viewMatrix)
        var lightCount = lightData.count
        renderCommandEncoder.setFragmentBytes(&lightCount, 
                                              length: Int32.size,
                                              index: TFSBufferDirectionalLightsNum.index)
        renderCommandEncoder.setFragmentBytes(&lightData,
                                              length: LightData.stride(lightCount),
                                              index: TFSBufferDirectionalLightData.index)
    }
    
    public static func setPointLightData(_ renderCommandEncoder: MTLRenderCommandEncoder) {
        var pointLightData = Self.getPointLightData()
//        var lightCount = lightData.count
//        renderCommandEncoder.setFragmentBytes(&lightCount,
//                                              length: Int32.size,
//                                              index: Int(TFSBufferPointLightsData.rawValue))
        
        renderCommandEncoder.setVertexBytes(&pointLightData,
                                            length: LightData.stride(pointLightData.count),
                                            index: TFSBufferPointLightsData.index)
        
        renderCommandEncoder.setFragmentBytes(&pointLightData,
                                              length: LightData.stride(pointLightData.count),
                                              index: TFSBufferPointLightsData.index)
    }
}
