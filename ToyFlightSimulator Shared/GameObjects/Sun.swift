//
//  Sun.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

class Sun: LightObject {
    init() {
        super.init(name: "Sun", lightType: Directional)
        self.setScale(float3(repeating: 0.3))
    }
    
    init(modelType: ModelType) {
        super.init(name: "Sun", lightType: Directional, modelType: modelType)
        self.setScale(float3(repeating: 0.3))
    }
}
