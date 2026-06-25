//
//  ModelLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/13/24.
//

import MetalKit
import os

enum ModelType {
    case None
    
    case Triangle
    case Cube
    case Capsule
    case Sphere
    case Quad
    
    case SkySphere
    case Skybox
    
    case F16
    case F18
    
    case RC_F18
    
    case CGTrader_F35
    case CGTrader_F22
    
    case Sketchfab_F35
    case Sketchfab_F22
    
    case Plane
    case Icosahedron
    case Temple
    
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

final class ModelLibrary: Library<ModelType, Model>, @unchecked Sendable {
    // Factories describe *how* to build each model; they are not invoked until
    // that model is first requested (lazy load).
    private var _factories: [ModelType: () -> Model] = [:]
    private var _cache: [ModelType: Model] = [:]
    private let _lock = OSAllocatedUnfairLock()

    override func makeLibrary() {
        let rotate180AroundY = Transform.rotationMatrix(radians: Float(180).toRadians, axis: Y_AXIS)

        _factories[.None]     = { Model(name: "No Mesh", mesh: NoMesh()) }
        _factories[.Triangle] = { Model(name: "Triangle", mesh: ProgrammaticTriangleMesh()) }
        _factories[.Cube]     = { Model(name: "Cube", mesh: CubeMesh()) }
        _factories[.Capsule]  = { Model(name: "Capsule", mesh: CapsuleMesh()) }
        _factories[.Skybox]   = { Model(name: "Skybox", mesh: SkyboxMesh()) }

        _factories[.Sphere]    = { ObjModel("sphere") }
        _factories[.Quad]      = { ObjModel("quad") }
        _factories[.SkySphere] = { ObjModel("skysphere") }

        _factories[.F16] = { ObjModel("f16r", basisTransform: rotate180AroundY) }
        _factories[.F18] = { ObjModel("FA-18F", basisTransform: rotate180AroundY) }

//        _factories[.RC_F18] = { UsdModel("FA-18F") }

        _factories[.CGTrader_F22] = {
            UsdModel("cgtrader_F22",
                     fileExtension: .USDZ,
                     basisTransform: Transform.transformXMinusZYToXYZ)
        }

        _factories[.Sketchfab_F35] = { UsdModel("F-35A_Lightning_II") }

        _factories[.Sketchfab_F22] = {
            UsdModel("F-22_Raptor", basisTransform: Transform.transformYMinusZXToXYZ)
        }

        _factories[.Plane]       = { Model(name: "Plane", mesh: PlaneMesh()) }
        _factories[.Icosahedron] = { Model(name: "Icosahedron", mesh: IcosahedronMesh()) }
        _factories[.Temple]      = { ObjModel("Temple") }

        // -----------------------------------

        _factories[.F18_Sidewinder_Left] = {
            Model(name: "F18_AIM9_Left", mesh: Assets.SingleSMMeshes[.F18_Sidewinder_Left])
        }
        _factories[.F18_AIM120_Left] = {
            Model(name: "F18_AIM120_Left", mesh: Assets.SingleSMMeshes[.F18_AIM120_Left])
        }
        _factories[.F18_GBU16_Left] = {
            Model(name: "F18_GBU16_Left", mesh: Assets.SingleSMMeshes[.F18_GBU16_Left])
        }

        _factories[.F18_Sidewinder_Right] = {
            Model(name: "F18_AIM9_Right", mesh: Assets.SingleSMMeshes[.F18_Sidewinder_Right])
        }
        _factories[.F18_AIM120_Right] = {
            Model(name: "F18_AIM120_Right", mesh: Assets.SingleSMMeshes[.F18_AIM120_Right])
        }
        _factories[.F18_GBU16_Right] = {
            Model(name: "F18_GBU16_Right", mesh: Assets.SingleSMMeshes[.F18_GBU16_Right])
        }

        _factories[.F18_FuelTank_Left] = {
            Model(name: "F18_FuelTank_Left", mesh: Assets.SingleSMMeshes[.F18_FuelTank_Left])
        }
        _factories[.F18_FuelTank_Center] = {
            Model(name: "F18_FuelTank_Center", mesh: Assets.SingleSMMeshes[.F18_FuelTank_Center])
        }
        _factories[.F18_FuelTank_Right] = {
            Model(name: "F18_FuelTank_Right", mesh: Assets.SingleSMMeshes[.F18_FuelTank_Right])
        }

        _factories[.F18_Aileron_Left]  = { Model(name: "F18_Aileron_Left",  mesh: Assets.SingleSMMeshes[.F18_Aileron_Left]) }
        _factories[.F18_Aileron_Right] = { Model(name: "F18_Aileron_Right", mesh: Assets.SingleSMMeshes[.F18_Aileron_Right]) }
        _factories[.F18_Elevon_Left]   = { Model(name: "F18_Elevon_Left",   mesh: Assets.SingleSMMeshes[.F18_Elevon_Left]) }
        _factories[.F18_Elevon_Right]  = { Model(name: "F18_Elevon_Right",  mesh: Assets.SingleSMMeshes[.F18_Elevon_Right]) }
        _factories[.F18_Flap_Left]     = { Model(name: "F18_Flap_Left",     mesh: Assets.SingleSMMeshes[.F18_Flap_Left]) }
        _factories[.F18_Flap_Right]    = { Model(name: "F18_Flap_Right",    mesh: Assets.SingleSMMeshes[.F18_Flap_Right]) }
        _factories[.F18_Rudder_Left]   = { Model(name: "F18_Rudder_Left",   mesh: Assets.SingleSMMeshes[.F18_Rudder_Left]) }
        _factories[.F18_Rudder_Right]  = { Model(name: "F18_Rudder_Right",  mesh: Assets.SingleSMMeshes[.F18_Rudder_Right]) }
    }

    override subscript(type: ModelType) -> Model {
        withLock(_lock) {
            if let cached = _cache[type] { return cached }
            let model = _factories[type]!()
            _cache[type] = model
            return model
        }
    }
}
