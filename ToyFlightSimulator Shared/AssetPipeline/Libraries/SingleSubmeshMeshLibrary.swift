//
//  SingleSMMeshLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/5/23.
//

import MetalKit
import os

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

final class SingleSubmeshMeshLibrary: Library<SingleSMMeshType, SingleSubmeshMesh>, @unchecked Sendable {
    // Factories describe *how* to extract each submesh; they are not invoked
    // until that submesh is first requested (lazy load). Each call reloads the
    // "FA-18F" model, so deferring them keeps the parent file off the heap
    // entirely for scenes that never use F-18 parts.
    private var _factories: [SingleSMMeshType: () -> SingleSubmeshMesh] = [:]
    private var _cache: [SingleSMMeshType: SingleSubmeshMesh] = [:]
    private let _lock = OSAllocatedUnfairLock()

    override func makeLibrary() {
        let rotate180AroundY = Transform.rotationMatrix(radians: Float(180).toRadians, axis: Y_AXIS)

        // Every submesh comes from the same "FA-18F" model with the same basis;
        // only the submesh name varies.
        func factory(_ submeshName: String) -> () -> SingleSubmeshMesh {
            { SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F",
                                                            submeshName: submeshName,
                                                            basisTransform: rotate180AroundY) }
        }

        _factories[.F18_Sidewinder_Left]  = factory("AIM-9XL_Paint")
        _factories[.F18_AIM120_Left]      = factory("AIM-120DL_Paint")
        _factories[.F18_GBU16_Left]       = factory("GBU-16L_Paint")

        _factories[.F18_Sidewinder_Right] = factory("AIM-9XR_Paint")
        _factories[.F18_AIM120_Right]     = factory("AIM-120DR_Paint")
        _factories[.F18_GBU16_Right]      = factory("GBU-16R_Paint")

        _factories[.F18_FuelTank_Left]    = factory("TankWingL_Paint")
        _factories[.F18_FuelTank_Center]  = factory("TankCenter_Paint")
        _factories[.F18_FuelTank_Right]   = factory("TankWingR_Paint")

        _factories[.F18_Aileron_Left]     = factory("EleronsL_Paint")
        _factories[.F18_Aileron_Right]    = factory("EleronsR_Paint")

        _factories[.F18_Elevon_Left]      = factory("ElevatorL_Paint")
        _factories[.F18_Elevon_Right]     = factory("ElevatorR_Paint")

        _factories[.F18_Flap_Left]        = factory("FlapsL_Paint")
        _factories[.F18_Flap_Right]       = factory("FlapsR_Paint")

        _factories[.F18_Rudder_Left]      = factory("RudderL_Paint")
        _factories[.F18_Rudder_Right]     = factory("RudderR_Paint")
    }

    override subscript(type: SingleSMMeshType) -> SingleSubmeshMesh {
        withLock(_lock) {
            if let cached = _cache[type] { return cached }
            let mesh = _factories[type]!()
            _cache[type] = mesh
            return mesh
        }
    }
}
