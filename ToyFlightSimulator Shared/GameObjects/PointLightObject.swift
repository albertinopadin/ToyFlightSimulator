//
//  PointLightObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 12/10/23.
//

class PointLightObject: LightObject {
    init() {
        super.init(name: "Point Light", lightType: .Point, meshType: .Icosahedron)
    }
}
