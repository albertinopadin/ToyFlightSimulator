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

    // Landing Gear - Nose
    case F18_NoseGear_Strut
    case F18_NoseGear_Wheels
    case F18_NoseGear_DoorLeft
    case F18_NoseGear_DoorRight

    // Landing Gear - Main Left
    case F18_MainGearL_Strut
    case F18_MainGearL_Wheel
    case F18_MainGearL_Door

    // Landing Gear - Main Right
    case F18_MainGearR_Strut
    case F18_MainGearR_Wheel
    case F18_MainGearR_Door
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

        // Landing Gear - Nose
        let f18NoseGearStrut = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "MainStrut_Paint")
        let f18NoseGearWheels = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "NoseWheels_Paint")
        let f18NoseGearDoorLeft = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "NoseDoors1A_Paint")
        let f18NoseGearDoorRight = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "NoseDoors1B_Paint")

        _library.updateValue(f18NoseGearStrut, forKey: .F18_NoseGear_Strut)
        _library.updateValue(f18NoseGearWheels, forKey: .F18_NoseGear_Wheels)
        _library.updateValue(f18NoseGearDoorLeft, forKey: .F18_NoseGear_DoorLeft)
        _library.updateValue(f18NoseGearDoorRight, forKey: .F18_NoseGear_DoorRight)

        // Landing Gear - Main Left
        let f18MainGearLStrut = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "MainStrutL_Paint")
        let f18MainGearLWheel = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "WheelMainL_Paint")
        let f18MainGearLDoor = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "GearDoors1L_Paint")

        _library.updateValue(f18MainGearLStrut, forKey: .F18_MainGearL_Strut)
        _library.updateValue(f18MainGearLWheel, forKey: .F18_MainGearL_Wheel)
        _library.updateValue(f18MainGearLDoor, forKey: .F18_MainGearL_Door)

        // Landing Gear - Main Right
        let f18MainGearRStrut = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "MainStrutR_Paint")
        let f18MainGearRWheel = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "WheelMainR_Paint")
        let f18MainGearRDoor = SingleSubmeshMesh.createSingleSMMeshFromModel(modelName: "FA-18F", submeshName: "GearDoors1R_Paint")

        _library.updateValue(f18MainGearRStrut, forKey: .F18_MainGearR_Strut)
        _library.updateValue(f18MainGearRWheel, forKey: .F18_MainGearR_Wheel)
        _library.updateValue(f18MainGearRDoor, forKey: .F18_MainGearR_Door)
    }
    
    override subscript(type: SingleSMMeshType) -> SingleSubmeshMesh {
        return _library[type]!
    }
}

