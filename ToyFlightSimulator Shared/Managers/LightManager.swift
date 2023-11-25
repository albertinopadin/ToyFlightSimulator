//
//  LightManager.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

import MetalKit

class LightManager {
    private var _lightObjects: [LightObject] = []
    
    func addLightObject(_ lightObject: LightObject) {
        self._lightObjects.append(lightObject)
    }
    
    private func gatherLightData() -> [LightData] {
        var result: [LightData] = []
        for lightObject in _lightObjects {
            result.append(lightObject.lightData)
        }
        return result
    }
    
    func setLightData(_ renderCommandEncoder: MTLRenderCommandEncoder) {
        var lightDatas = gatherLightData()
        var lightCount = lightDatas.count
        renderCommandEncoder.setFragmentBytes(&lightCount, 
                                              length: Int32.size,
                                              index: Int(TFSBufferDirectionalLightsNum.rawValue))
        renderCommandEncoder.setFragmentBytes(&lightDatas,
                                              length: LightData.stride(lightCount),
                                              index: Int(TFSBufferDirectionalLightData.rawValue))
    }
    
    func getDirectionalLightData() -> LightData? {
//        print("[getDirectionalLightData] number of light objects: \(_lightObjects.count)")
        for _lightObject in _lightObjects {
            if _lightObject.type == .Directional {
                return _lightObject.lightData
            }
        }
        
        return nil
    }
    
    func getPointLightData() -> [LightData] {
        _lightObjects.filter({ $0.type == .Point }).map { $0.lightData }
    }
}
