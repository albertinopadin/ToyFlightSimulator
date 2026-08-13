//
//  PointLightObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 12/10/23.
//

class PointLightObject: LightObject {
    // LightData's extension init defaults radius to 1 m — technically valid but barely
    // visible. Default point lights to a usable 10 m; scenes override via the parameter
    // or setLightRadius.
    init(radius: Float = 10) {
        super.init(name: "Point Light", lightType: Point, modelType: .Icosahedron)
        setLightRadius(radius)
    }
}
