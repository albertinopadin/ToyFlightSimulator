//
//  F18.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 2/11/23.
//

import MetalKit

class F18: Aircraft {
    private let _cameraPositionOffset = float3(0, 10, 20)
    
    var stores: [String] = [
        "AIM-9XL_Paint",
        "AIM-9XR_Paint",
        "AIM-120DL_Paint",
        "AIM-120DR_Paint",
        "GBU-16L_Paint",
        "GBU-16R_Paint",
        "TankWingL_Paint",
        "TankWingR_Paint",
        "TankCenter_Paint"
    ]
    
    var storesLeft: Int
    
//    var landingGear: [String] = [
//
//    ]
    
    var movables: [String] = [
        "CanopyFront_Paint",
        "Canopy_Paint",
        "ElevatorL_Paint",
        "ElevatorR_Paint",
        "RudderL_Paint",
        "RudderR_Paint",
        "TailL_Paint",
        "TailR_Paint",
        "HookBox_Paint",
        "Hook_Paint",
        "WingFoldL_Paint",
        "WingFoldR_Paint",
        "SlatsInnerL_Paint",
        "SlatsInnerR_Paint",
        "SlatsOuterL_Paint",
        "SlatsOuterR_Paint",
        "FlapsL_Paint",
        "FlapsR_Paint",
        "EleronsL_Paint",
        "EleronsR_Paint",
        "EngineNozzles_Paint",
        "EleronGearBox_Paint",
        "SeatFront_Paint",
        "SeatBack_Paint",
        "AirbrakeBox_Paint",
        "AirbrakeTBox_Paint",
        "FrontGearBox_Paint",
        "LandingGearBox_Paint",
        "AirbrakeL_Paint",
        "AirbrakeR_Paint",
        "AirbrakeT_Paint",
        "NoseDoors1A_Paint",
        "NoseDoors1B_Paint",
        "NoseDoors2_Paint",
        "NoseDoors3_Paint",
        "GearDoors1L_Paint",
        "GearDoors1R_Paint",
        "GearDoors2L_Paint",
        "GearDoors2R_Paint",
        "GearDoors3L_Paint",
        "GearDoors3R_Paint",
        "TopStrut_Paint",
        "MainStrut_Paint",
        "UpperStrut_Paint",
        "MidStrut_Paint",
        "LowerStrut_Paint",
        "MidRing_Paint",
        "CatobarHook_Paint",
        "BackStrut_Paint",
        "BackStrut1_Paint",
        "BackStrut2_Paint",
        "NoseWheels_Paint",
        "MainStrutL_Paint",
        "MainStrutR_Paint",
        "TopStrutL_Paint",
        "TopStrutR_Paint",
        "MidStrutL_Paint",
        "MidStrutLR_Paint",
        "LowerStrutL_Paint",
        "LowerStrutR_Paint",
        "WheelMainL_Paint",
        "WheelMainR_Paint",
        "CanopyGlass_Glass",
        "CanopyGlassFront_Glass"
    ]
    
    var submeshesToDisplay: [String: Bool] = [
        "Fuselage_Paint": true,
        "Nose_Paint": true,
        "NoseSensor_Paint": true,
        "Sensor_Paint": true,
        "Antennas_Paint": true,
        "CanopyFront_Paint": true,
        "Canopy_Paint": true,
        "IntakeL_Paint": true,
        "IntakeR_Paint": true,
        "Inlets_Paint": true,
        "ElevatorL_Paint": true,
        "ElevatorR_Paint": true,
        "RudderL_Paint": true,
        "RudderR_Paint": true,
        "TailL_Paint": true,
        "TailR_Paint": true,
        "HookBox_Paint": true,
        "Hook_Paint": true,
        "WingFoldL_Paint": true,
        "WingFoldR_Paint": true,
        "SlatsInnerL_Paint": true,
        "SlatsInnerR_Paint": true,
        "SlatsOuterL_Paint": true,
        "SlatsOuterR_Paint": true,
        "FlapsL_Paint": true,
        "FlapsR_Paint": true,
        "EleronsL_Paint": true,
        "EleronsR_Paint": true,
        "EngineNozzles_Paint": true,
        "EleronGearBox_Paint": true,
        "Cockpit_Paint": true,
        "Furniture_Paint": true,
        "SeatFront_Paint": true,
        "SeatBack_Paint": true,
        "AirbrakeBox_Paint": true,
        "AirbrakeTBox_Paint": true,
        "FrontGearBox_Paint": true,
        "LandingGearBox_Paint": true,
        "AirbrakeL_Paint": true,
        "AirbrakeR_Paint": true,
        "AirbrakeT_Paint": true,
        "NoseDoors1A_Paint": true,
        "NoseDoors1B_Paint": true,
        "NoseDoors2_Paint": true,
        "NoseDoors3_Paint": true,
        "GearDoors1L_Paint": true,
        "GearDoors1R_Paint": true,
        "GearDoors2L_Paint": true,
        "GearDoors2R_Paint": true,
        "GearDoors3L_Paint": true,
        "GearDoors3R_Paint": true,
        "TopStrut_Paint": true,
        "MainStrut_Paint": true,
        "UpperStrut_Paint": true,
        "MidStrut_Paint": true,
        "LowerStrut_Paint": true,
        "MidRing_Paint": true,
        "CatobarHook_Paint": true,
        "BackStrut_Paint": true,
        "BackStrut1_Paint": true,
        "BackStrut2_Paint": true,
        "NoseWheels_Paint": true,
        "MainStrutL_Paint": true,
        "MainStrutR_Paint": true,
        "TopStrutL_Paint": true,
        "TopStrutR_Paint": true,
        "MidStrutL_Paint": true,
        "MidStrutLR_Paint": true,
        "LowerStrutL_Paint": true,
        "LowerStrutR_Paint": true,
        "WheelMainL_Paint": true,
        "WheelMainR_Paint": true,
        "PylonWingTipL_Paint": true,
        "PylonWingTipR_Paint": true,
        "PylonCenter_Paint": true,
        "Pylon1L_Paint": true,
        "Pylon1R_Paint": true,
        "Pylon2L_Paint": true,
        "Pylon2R_Paint": true,
        "Pylon3TopL_Paint": true,
        "Pylon3TopR_Paint": true,
        "Pylon3BottomL_Paint": true,
        "Pylon3BottomR_Paint": true,
        "TankWingL_Paint": true,
        "TankWingR_Paint": true,
        "TankCenter_Paint": true,
        "AIM-9XL_Paint": true,
        "AIM-9XR_Paint": true,
        "AIM-120DL_Paint": true,
        "AIM-120DR_Paint": true,
        "GBU-16L_Paint": true,
        "GBU-16R_Paint": true,
        "CanopyGlass_Glass": true,
        "CanopyGlassFront_Glass": true
    ]
    
    init() {
        self.storesLeft = stores.count
        super.init(name: "F-18", meshType: .F18, renderPipelineStateType: .OpaqueMaterial)
//        self.shouldUpdate = false  // Don't update when user moves camera
    }
    
    init(camera: AttachedCamera, scale: Float = 0.5) {
        self.storesLeft = stores.count
        super.init(name: "F-18",
                   meshType: .F18,
                   renderPipelineStateType: .OpaqueMaterial,
                   camera: camera,
                   cameraOffset: _cameraPositionOffset,
                   scale: scale)
    }
    
    override func doUpdate() {
//        if shouldUpdate {
//            super.doUpdate()
//        }
        
        if Keyboard.IsKeyPressed(.space) {
            print("[F18 doUpdate] Pressed Space!")
            if storesLeft > 0 {
                let storeToReleaseIdx = stores.count - storesLeft
                let storeToRelease = stores[storeToReleaseIdx]
                print("Store to release: \(storeToRelease)")
                submeshesToDisplay[storeToRelease] = false
                storesLeft -= 1
            }
        }
    }
    
    override func doRender(_ renderCommandEncoder: MTLRenderCommandEncoder,
                           applyMaterials: Bool = true,
                           submeshesToRender: [String : Bool]? = nil) {
        super.doRender(renderCommandEncoder, applyMaterials: applyMaterials, submeshesToRender: submeshesToDisplay)
    }
    
    override func doRenderShadow(_ renderCommandEncoder: MTLRenderCommandEncoder, submeshesToRender: [String : Bool]?) {
        super.doRenderShadow(renderCommandEncoder, submeshesToRender: submeshesToDisplay)
    }
}
