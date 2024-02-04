//
//  LightManager.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

import MetalKit

class LightManager {
    private var _lightObjects: [LightObject] = []
    
    public func addLightObject(_ lightObject: LightObject) {
        self._lightObjects.append(lightObject)
    }
    
    public func getLightObjects(lightType: LightType) -> [LightObject] {
        return _lightObjects.filter { $0.lightType == lightType }
    }

    public func getDirectionalLightData(viewMatrix: float4x4) -> [LightData] {
        let lightObjs = getLightObjects(lightType: .Directional)
        lightObjs.forEach { $0.lightData.lightEyeDirection = normalize(viewMatrix * float4(-$0.getPosition(), 1)).xyz }
        return lightObjs.map { $0.lightData }
    }
    
    public func getPointLightData() -> [LightData] {
        return getLightObjects(lightType: .Point).map { $0.lightData }
    }
    
    public func setDirectionalLightData(_ renderCommandEncoder: MTLRenderCommandEncoder,
                                        cameraPosition: float3,
                                        viewMatrix: float4x4) {
        var lightData = getDirectionalLightData(viewMatrix: viewMatrix)
        var lightCount = lightData.count
        renderCommandEncoder.setFragmentBytes(&lightCount, 
                                              length: Int32.size,
                                              index: Int(TFSBufferDirectionalLightsNum.rawValue))
        renderCommandEncoder.setFragmentBytes(&lightData,
                                              length: LightData.stride(lightCount),
                                              index: Int(TFSBufferDirectionalLightData.rawValue))
    }
    
    public func setPointLightData(_ renderCommandEncoder: MTLRenderCommandEncoder) {
        var pointLightData = getPointLightData()
//        var lightCount = lightData.count
//        renderCommandEncoder.setFragmentBytes(&lightCount,
//                                              length: Int32.size,
//                                              index: Int(TFSBufferPointLightsData.rawValue))
        
        renderCommandEncoder.setVertexBytes(&pointLightData,
                                            length: LightData.stride(pointLightData.count),
                                            index: Int(TFSBufferPointLightsData.rawValue))
        
        renderCommandEncoder.setFragmentBytes(&pointLightData,
                                              length: LightData.stride(pointLightData.count),
                                              index: Int(TFSBufferPointLightsData.rawValue))
    }
}
