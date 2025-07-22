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

final class SingleSubmeshMeshLibrary: Library<SingleSMMeshType, SingleSubmeshMesh>, @unchecked Sendable {
    private var _library: [SingleSMMeshType: SingleSubmeshMesh] = [:]
    
    override func makeLibrary() {
        let f18SidewinderLeft = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "AIM-9XL_Paint")
        let f18AIM120Left = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "AIM-120DL_Paint")
        let f18GBU16Left = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "GBU-16L_Paint")
        
        let f18SidewinderRight = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "AIM-9XR_Paint")
        let f18AIM120Right = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "AIM-120DR_Paint")
        let f18GBU16Right = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "GBU-16R_Paint")
        
        let f18FuelTankLeft = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "TankWingL_Paint")
        let f18FuelTankCenter = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "TankCenter_Paint")
        let f18FuelTankRight = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "TankWingR_Paint")
        
        let f18LeftAileron = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "EleronsL_Paint")
        let f18RightAileron = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "EleronsR_Paint")
        
        let f18LeftElevon = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "ElevatorL_Paint")
        let f18RightElevon = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "ElevatorR_Paint")
        
        let f18LeftFlap = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "FlapsL_Paint")
        let f18RightFlap = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "FlapsR_Paint")
        
        let f18LeftRudder = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "RudderL_Paint")
        let f18RightRudder = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "RudderR_Paint")
        
        _library.updateValue(f18SidewinderLeft, forKey: .F18_Sidewinder_Left)
        _library.updateValue(f18AIM120Left, forKey: .F18_AIM120_Left)
        _library.updateValue(f18GBU16Left, forKey: .F18_GBU16_Left)
        
        _library.updateValue(f18SidewinderRight, forKey: .F18_Sidewinder_Right)
        _library.updateValue(f18AIM120Right, forKey: .F18_AIM120_Right)
        _library.updateValue(f18GBU16Right, forKey: .F18_GBU16_Right)
        
        _library.updateValue(f18FuelTankLeft, forKey: .F18_FuelTank_Left)
        _library.updateValue(f18FuelTankCenter, forKey: .F18_FuelTank_Center)
        _library.updateValue(f18FuelTankRight, forKey: .F18_FuelTank_Right)
        
        _library.updateValue(f18LeftAileron, forKey: .F18_Aileron_Left)
        _library.updateValue(f18RightAileron, forKey: .F18_Aileron_Right)
        
        _library.updateValue(f18LeftElevon, forKey: .F18_Elevon_Left)
        _library.updateValue(f18RightElevon, forKey: .F18_Elevon_Right)
        
        _library.updateValue(f18LeftFlap, forKey: .F18_Flap_Left)
        _library.updateValue(f18RightFlap, forKey: .F18_Flap_Right)
        
        _library.updateValue(f18LeftRudder, forKey: .F18_Rudder_Left)
        _library.updateValue(f18RightRudder, forKey: .F18_Rudder_Right)
    }
    
    override subscript(type: SingleSMMeshType) -> SingleSubmeshMesh {
        return _library[type]!
    }
}

