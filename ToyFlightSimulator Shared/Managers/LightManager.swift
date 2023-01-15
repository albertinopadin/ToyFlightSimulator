//
//  LightManager.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

import MetalKit

class LightManager {
    var lightObjects: [LightObject] = []
    
    func addLightObject(_ lightObject: LightObject) {
        self.lightObjects.append(lightObject)
    }
    
    private func gatherLightData() -> [LightData] {
        var result: [LightData] = []
        for lightObject in lightObjects {
            result.append(lightObject.lightData)
        }
        return result
    }
    
    func setLightData(_ renderCommandEncoder: MTLRenderCommandEncoder) {
        var lightDatas = gatherLightData()
        var lightCount = lightDatas.count
        renderCommandEncoder.setFragmentBytes(&lightCount, length: Int32.size, index: 2)
        renderCommandEncoder.setFragmentBytes(&lightDatas, length: LightData.stride(lightCount), index: 3)
    }
}
