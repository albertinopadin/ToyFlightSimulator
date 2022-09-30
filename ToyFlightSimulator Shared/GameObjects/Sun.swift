//
//  Sun.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

class Sun: LightObject {
    init() {
        super.init(name: "Sun")
        self.setScale(float3(repeating: 0.3))
    }
}
