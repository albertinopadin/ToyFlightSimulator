//
//  ModelLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/13/24.
//

import MetalKit

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
    private var _library: [ModelType: Model] = [:]
    
    override func makeLibrary() {
        _library.updateValue(Model(name: "No Mesh", mesh: NoMesh()), forKey: .None)
        _library.updateValue(Model(name: "Triangle", mesh: TriangleMesh()), forKey: .Triangle)
        _library.updateValue(Model(name: "Cube", mesh: CubeMesh()), forKey: .Cube)
        _library.updateValue(Model(name: "Capsule", mesh: CapsuleMesh()), forKey: .Capsule)
        _library.updateValue(Model(name: "Skybox", mesh: SkyboxMesh()), forKey: .Skybox)
        
        _library.updateValue(ObjModel("sphere"), forKey: .Sphere)
        _library.updateValue(ObjModel("quad"), forKey: .Quad)
        _library.updateValue(ObjModel("skysphere"), forKey: .SkySphere)
        
        _library.updateValue(ObjModel("f16r"), forKey: .F16)
        _library.updateValue(ObjModel("FA-18F"), forKey: .F18)
        
        _library.updateValue(UsdModel("FA-18F"), forKey: .RC_F18)
        _library.updateValue(UsdModel("F-35A_Lightning_II", transform: Transform.transformXZYToXYZ), forKey: .Sketchfab_F35)
        _library.updateValue(UsdModel("F-22_Raptor", transform: Transform.transformZXYToXYZ), forKey: .Sketchfab_F22)
        
        _library.updateValue(Model(name: "Plane", mesh: PlaneMesh()), forKey: .Plane)
        _library.updateValue(Model(name: "Icosahedron", mesh: IcosahedronMesh()), forKey: .Icosahedron)
        _library.updateValue(ObjModel("Temple"), forKey: .Temple)
        
        // -----------------------------------
        
        _library.updateValue(Model(name: "F18_AIM9_Left", mesh: Assets.SingleSMMeshes[.F18_Sidewinder_Left]),
                             forKey: .F18_Sidewinder_Left)
        _library.updateValue(Model(name: "F18_AIM120_Left", mesh: Assets.SingleSMMeshes[.F18_AIM120_Left]),
                             forKey: .F18_AIM120_Left)
        _library.updateValue(Model(name: "F18_GBU16_Left", mesh: Assets.SingleSMMeshes[.F18_GBU16_Left]),
                             forKey: .F18_GBU16_Left)
        
        _library.updateValue(Model(name: "F18_AIM9_Right", mesh: Assets.SingleSMMeshes[.F18_Sidewinder_Right]),
                             forKey: .F18_Sidewinder_Right)
        _library.updateValue(Model(name: "F18_AIM120_Right", mesh: Assets.SingleSMMeshes[.F18_AIM120_Right]),
                             forKey: .F18_AIM120_Right)
        _library.updateValue(Model(name: "F18_GBU16_Right", mesh: Assets.SingleSMMeshes[.F18_GBU16_Right]),
                             forKey: .F18_GBU16_Right)
        
        _library.updateValue(Model(name: "F18_FuelTank_Left", mesh: Assets.SingleSMMeshes[.F18_FuelTank_Left]),
                             forKey: .F18_FuelTank_Left)
        _library.updateValue(Model(name: "F18_FuelTank_Center", mesh: Assets.SingleSMMeshes[.F18_FuelTank_Center]),
                             forKey: .F18_FuelTank_Center)
        _library.updateValue(Model(name: "F18_FuelTank_Right", mesh: Assets.SingleSMMeshes[.F18_FuelTank_Right]),
                             forKey: .F18_FuelTank_Right)
        
        let leftAileronMesh = Assets.SingleSMMeshes[.F18_Aileron_Left]
        let rightAileronMesh = Assets.SingleSMMeshes[.F18_Aileron_Right]
        let leftElevonMesh = Assets.SingleSMMeshes[.F18_Elevon_Left]
        let rightElevonMesh = Assets.SingleSMMeshes[.F18_Elevon_Right]
        let leftFlapMesh = Assets.SingleSMMeshes[.F18_Flap_Left]
        let rightFlapMesh = Assets.SingleSMMeshes[.F18_Flap_Right]
        let leftRudderMesh = Assets.SingleSMMeshes[.F18_Rudder_Left]
        let rightRudderMesh = Assets.SingleSMMeshes[.F18_Rudder_Right]
        
        _library.updateValue(Model(name: "F18_Aileron_Left", mesh: leftAileronMesh), forKey: .F18_Aileron_Left)
        _library.updateValue(Model(name: "F18_Aileron_Right", mesh: rightAileronMesh), forKey: .F18_Aileron_Right)
        _library.updateValue(Model(name: "F18_Elevon_Left", mesh: leftElevonMesh), forKey: .F18_Elevon_Left)
        _library.updateValue(Model(name: "F18_Elevon_Right", mesh: rightElevonMesh), forKey: .F18_Elevon_Right)
        _library.updateValue(Model(name: "F18_Flap_Left", mesh: leftFlapMesh), forKey: .F18_Flap_Left)
        _library.updateValue(Model(name: "F18_Flap_Right", mesh: rightFlapMesh), forKey: .F18_Flap_Right)
        _library.updateValue(Model(name: "F18_Rudder_Left", mesh: leftRudderMesh), forKey: .F18_Rudder_Left)
        _library.updateValue(Model(name: "F18_Rudder_Right", mesh: rightRudderMesh), forKey: .F18_Rudder_Right)
    }
    
    override subscript(type: ModelType) -> Model {
        return _library[type]!
    }
}
