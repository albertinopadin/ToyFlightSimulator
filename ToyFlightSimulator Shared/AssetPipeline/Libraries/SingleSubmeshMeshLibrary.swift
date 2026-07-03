//
//  SingleSMMeshLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/5/23.
//

import MetalKit

enum SingleSMMeshType {
    case F18_Sidewinder_Left
    case F18_AIM120_Left
    case F18_GBU16_Left

    case F18_Sidewinder_Right
    case F18_AIM120_Right
    case F18_GBU16_Right

    case F18_FuelTank_Left
    case F18_FuelTank_Center
    case F18_FuelTank_Right

    case F18_Aileron_Left
    case F18_Aileron_Right
    case F18_Elevon_Left
    case F18_Elevon_Right
    case F18_Flap_Left
    case F18_Flap_Right
    case F18_Rudder_Left
    case F18_Rudder_Right
}

// Submeshes are extracted on first request (lazy load). Each extraction loads
// the "FA-18F" parent model, so deferring keeps the parent file off the heap
// entirely for scenes that never use F-18 parts.
final class SingleSubmeshMeshLibrary: LazyLibrary<SingleSMMeshType, SingleSubmeshMesh>, @unchecked Sendable {
    override func makeLibrary() {
        let rotate180AroundY = Transform.rotationMatrix(radians: Float(180).toRadians, axis: Y_AXIS)

        // Every submesh comes from the same "FA-18F" model with the same basis;
        // only the submesh name varies.
        func factory(_ submeshName: String) -> () -> SingleSubmeshMesh {
            { SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F",
                                                            submeshName: submeshName,
                                                            basisTransform: rotate180AroundY) }
        }

        register(.F18_Sidewinder_Left,  factory("AIM-9XL_Paint"))
        register(.F18_AIM120_Left,      factory("AIM-120DL_Paint"))
        register(.F18_GBU16_Left,       factory("GBU-16L_Paint"))

        register(.F18_Sidewinder_Right, factory("AIM-9XR_Paint"))
        register(.F18_AIM120_Right,     factory("AIM-120DR_Paint"))
        register(.F18_GBU16_Right,      factory("GBU-16R_Paint"))

        register(.F18_FuelTank_Left,    factory("TankWingL_Paint"))
        register(.F18_FuelTank_Center,  factory("TankCenter_Paint"))
        register(.F18_FuelTank_Right,   factory("TankWingR_Paint"))

        register(.F18_Aileron_Left,     factory("EleronsL_Paint"))
        register(.F18_Aileron_Right,    factory("EleronsR_Paint"))

        register(.F18_Elevon_Left,      factory("ElevatorL_Paint"))
        register(.F18_Elevon_Right,     factory("ElevatorR_Paint"))

        register(.F18_Flap_Left,        factory("FlapsL_Paint"))
        register(.F18_Flap_Right,       factory("FlapsR_Paint"))

        register(.F18_Rudder_Left,      factory("RudderL_Paint"))
        register(.F18_Rudder_Right,     factory("RudderR_Paint"))
    }

    override subscript(type: SingleSMMeshType) -> SingleSubmeshMesh {
        guard let mesh = resolve(type) else {
            fatalError("[SingleSubmeshMeshLibrary] No mesh factory registered for type: \(type)")
        }
        return mesh
    }
}
