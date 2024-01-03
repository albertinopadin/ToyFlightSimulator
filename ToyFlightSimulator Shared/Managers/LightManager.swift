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
    
//    private func gatherLightData() -> [LightData] {
//        var result: [LightData] = []
//        for lightObject in _lightObjects {
//            result.append(lightObject.lightData)
//        }
//        return result
//    }
    
    public func getLightObjects(lightType: LightType) -> [LightObject] {
        return _lightObjects.filter { $0.lightType == lightType }
    }
    
//    func getDirectionalLightData() -> [LightData] {
//        var result: [LightData] = []
//        for _lightObject in _lightObjects {
//            if _lightObject.type == .Directional {
//                result.append(_lightObject.lightData)
//            }
//        }
//        return result
//    }

    public func getDirectionalLightData() -> [LightData] {
        return getLightObjects(lightType: .Directional).map { $0.lightData }
    }
    
    public func getPointLightData() -> [LightData] {
        return getLightObjects(lightType: .Point).map { $0.lightData }
//        let pointLights = getLightObjects(lightType: .Point)
//        print("Num point lights: \(pointLights.count)")
//        return pointLights.map { $0.lightData }
    }
    
    public func setDirectionalLightData(_ renderCommandEncoder: MTLRenderCommandEncoder) {
        var lightData = getDirectionalLightData()
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
        // TODO: Set point light count:
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
