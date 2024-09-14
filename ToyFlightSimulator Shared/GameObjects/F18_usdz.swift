//
//  F18_usdz.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/29/23.
//

import MetalKit

class F18Usdz: Aircraft {
    private var _spacePressed: Bool = false
    private var _mKeyPressed: Bool = false
    private var _nKeyPressed: Bool = false
    private var _jKeyPressed: Bool = false
    
    static let F18_ModelName = "FA-18F"
    
    static let AIM9Name = "AIM-9"
    static let AIM120Name = "AIM-120"
    static let GBU16Name = "GBU-16"
    static let FuelTankName = "FuelTank"
    static let NoseGearName = "NoseWheels"
    
    static let storesNames = [
        AIM9Name,
        AIM120Name,
        GBU16Name,
        FuelTankName
    ]
    
    let stores: [String: Store] = [
        AIM9Name: Store(remaining: 2, submeshNames: ["AIM-9XL", "AIM-9XR"]),
        AIM120Name: Store(remaining: 2, submeshNames: ["AIM-120DL", "AIM-120DR"]),
        GBU16Name: Store(remaining: 2, submeshNames: ["GBU-16L", "GBU-16R"]),
        FuelTankName: Store(remaining: 3, submeshNames: ["TankWingL", "TankWingR", "TankCenter"])
    ]
    
    
//    var landingGear: [String] = [
//
//    ]
    
    let noseWheelGearSubmeshNames: [String] = [
        "TopStrut",
        "MainStrut",
        "UpperStrut",
        "MidStrut",
        "LowerStrut",
        "MidRing",
        "CatobarHook",
        "BackStrut",
        "BackStrut1",
        "BackStrut2",
        "NoseWheels"
    ]
    
    var movables: [String] = [
        "CanopyFront",
        "Canopy",
        "ElevatorL",
        "ElevatorR",
        "RudderL",
        "RudderR",
        "TailL",
        "TailR",
        "HookBox",
        "Hook",
        "WingFoldL",
        "WingFoldR",
        "SlatsInnerL",
        "SlatsInnerR",
        "SlatsOuterL",
        "SlatsOuterR",
        "FlapsL",
        "FlapsR",
        "EleronsL",
        "EleronsR",
        "EngineNozzles",
        "EleronGearBox",
        "SeatFront",
        "SeatBack",
        "AirbrakeBox",
        "AirbrakeTBox",
        "FrontGearBox",
        "LandingGearBox",
        "AirbrakeL",
        "AirbrakeR",
        "AirbrakeT",
        "NoseDoors1A",
        "NoseDoors1B",
        "NoseDoors2",
        "NoseDoors3",
        "GearDoors1L",
        "GearDoors1R",
        "GearDoors2L",
        "GearDoors2R",
        "GearDoors3L",
        "GearDoors3R",
        "TopStrut",
        "MainStrut",
        "UpperStrut",
        "MidStrut",
        "LowerStrut",
        "MidRing",
        "CatobarHook",
        "BackStrut",
        "BackStrut1",
        "BackStrut2",
        "NoseWheels",
        "MainStrutL",
        "MainStrutR",
        "TopStrutL",
        "TopStrutR",
        "MidStrutL",
        "MidStrutLR",
        "LowerStrutL",
        "LowerStrutR",
        "WheelMainL",
        "WheelMainR",
        "CanopyGlass_Glass",
        "CanopyGlassFront_Glass"
    ]
    
    var submeshesToDisplay: [String: Bool] = [
        "Fuselage": true,
        "Nose": true,
        "NoseSensor": true,
        "Sensor": true,
        "Antennas": true,
        "CanopyFront": true,
        "Canopy": true,
        "IntakeL": true,
        "IntakeR": true,
        "Inlets": true,
        "ElevatorL": false,  // L Elevon
        "ElevatorR": false,  // R Elevon
        "RudderL": true,
        "RudderR": true,
        "TailL": true,
        "TailR": true,
        "HookBox": true,
        "Hook": true,
        "WingFoldL": true,
        "WingFoldR": true,
        "SlatsInnerL": true,
        "SlatsInnerR": true,
        "SlatsOuterL": true,
        "SlatsOuterR": true,
        "FlapsL": false,  // L Flap
        "FlapsR": false,  // R Flap
        "EleronsL": false,  // L Aileron
        "EleronsR": false,  // R Aileron
        "EngineNozzles": true,
        "EleronGearBox": true,
        "Cockpit": true,
        "Furniture": true,
        "SeatFront": true,
        "SeatBack": true,
        "AirbrakeBox": true,
        "AirbrakeTBox": true,
        "FrontGearBox": true,
        "LandingGearBox": true,
        "AirbrakeL": true,
        "AirbrakeR": true,
        "AirbrakeT": true,
        "NoseDoors1A": true,
        "NoseDoors1B": true,
        "NoseDoors2": true,
        "NoseDoors3": true,
        "GearDoors1L": true,
        "GearDoors1R": true,
        "GearDoors2L": true,
        "GearDoors2R": true,
        "GearDoors3L": true,
        "GearDoors3R": true,
        "TopStrut": true,  // TODO:: Need to rotate all of this to hide front gear...
        "MainStrut": true,
        "UpperStrut": true,
        "MidStrut": true,
        "LowerStrut": true,
        "MidRing": true,
        "CatobarHook": true,
        "BackStrut": true,
        "BackStrut1": true,
        "BackStrut2": true,
        "NoseWheels": true,
        "MainStrutL": true,
        "MainStrutR": true,
        "TopStrutL": true,
        "TopStrutR": true,
        "MidStrutL": true,
        "MidStrutLR": true,
        "LowerStrutL": true,
        "LowerStrutR": true,
        "WheelMainL": true,
        "WheelMainR": true,
        "PylonWingTipL": true,
        "PylonWingTipR": true,
        "PylonCenter": true,
        "Pylon1L": true,
        "Pylon1R": true,
        "Pylon2L": true,
        "Pylon2R": true,
        "Pylon3TopL": true,
        "Pylon3TopR": true,
        "Pylon3BottomL": true,
        "Pylon3BottomR": true,
        "TankWingL": true,
        "TankWingR": true,
        "TankCenter": true,
        "AIM-9XL": true,
        "AIM-9XR": true,
        "AIM-120DL": true,
        "AIM-120DR": true,
        "GBU-16L": true,
        "GBU-16R": true,
        "CanopyGlass_Glass": true,
        "CanopyGlassFront_Glass": true
    ]
    
    let nOriginZ: Float = 0.25
    
    let leftAileron = SubMeshGameObject(name: "Left_Aileron",
                                        modelName: F18_ModelName,
                                        submeshName: "EleronsL_Paint",
                                        renderPipelineStateType: .OpaqueMaterial)
    
    let rightAileron = SubMeshGameObject(name: "Right_Aileron",
                                         modelName: F18_ModelName,
                                         submeshName: "EleronsR_Paint",
                                         renderPipelineStateType: .OpaqueMaterial)
    
    let leftElevon = SubMeshGameObject(name: "Right_Elevon",
                                       modelName: F18_ModelName,
                                       submeshName: "ElevatorL_Paint",
                                       renderPipelineStateType: .OpaqueMaterial)
    
    let rightElevon = SubMeshGameObject(name: "Right_Elevon",
                                        modelName: F18_ModelName,
                                        submeshName: "ElevatorR_Paint",
                                        renderPipelineStateType: .OpaqueMaterial)
    
    let leftFlap = SubMeshGameObject(name: "Left_Flap",
                                     modelName: F18_ModelName,
                                     submeshName: "FlapsL_Paint",
                                     renderPipelineStateType: .OpaqueMaterial)
    
    let rightFlap = SubMeshGameObject(name: "Right_Flap",
                                      modelName: F18_ModelName,
                                      submeshName: "FlapsR_Paint",
                                      renderPipelineStateType: .OpaqueMaterial)
    
    var flapsDeployed: Bool = false
    var flapsDegrees: Float = 0.0
    var flapsBeganExtending: Bool = false
    var flapsFinishedExtending: Bool = false
    var flapsBeganRetracting: Bool = false
    var flapsFinishedRetracting: Bool = false
    
    let leftWingRearControlSurfaceRotationAxis = float3(-1, 0, 0.15)
    let rightWingRearControlSurfaceRotationAxis = float3(1, 0, 0.15)
    
    var landingGearDeployed: Bool = false
    var landingGearDegrees: Float = 0.0
    var landingGearBeganExtending: Bool = false
    var landingGearFinishedExtending: Bool = false
    var landingGearBeganRetracting: Bool = false
    var landingGearFinishedRetracting: Bool = false
    
    init(scale: Float = 1.0, shouldUpdate: Bool = true) {
        super.init(name: "F-18",
                   modelType: .RC_F18,
                   renderPipelineStateType: .OpaqueMaterial,
                   scale: scale,
                   shouldUpdate: shouldUpdate)
        setupControlSurfaces()
    }
    
    func setupControlSurfaces() {
        // Ailerons:
        let newAileronOrigin = float3(0, 0, nOriginZ)
        leftAileron.setSubmeshOrigin(newAileronOrigin)
        rightAileron.setSubmeshOrigin(newAileronOrigin)
        
        // Elevons:
        let newElevonOrigin = float3(0, 0, 1.0)
        leftElevon.setSubmeshOrigin(newElevonOrigin)
        rightElevon.setSubmeshOrigin(newElevonOrigin)
        
        // Flaps:
        let newFlapsOrigin = float3(0, 0, 0.50)
        leftFlap.setSubmeshOrigin(newFlapsOrigin)
        rightFlap.setSubmeshOrigin(newFlapsOrigin)
        
        // Set ailerons as children:
        let leftAileronMeshMetadata = leftAileron.getSubmeshVertexMetadata()
        let leftAileronPosition = leftAileronMeshMetadata.initialPositionInParentMesh - newAileronOrigin
        leftAileron.setPosition(leftAileronPosition)
        addChild(leftAileron)
        
        let rightAileronMeshMetadata = rightAileron.getSubmeshVertexMetadata()
        let rightAileronPosition = rightAileronMeshMetadata.initialPositionInParentMesh - newAileronOrigin
        rightAileron.setPosition(rightAileronPosition)
        addChild(rightAileron)
        
        // Set elevons as children:
        let leftElevonMeshMetadata = leftElevon.getSubmeshVertexMetadata()
        let leftElevonPosition = leftElevonMeshMetadata.initialPositionInParentMesh - newElevonOrigin
        leftElevon.setPosition(leftElevonPosition)
        addChild(leftElevon)
        
        let rightElevonMeshMetadata = rightElevon.getSubmeshVertexMetadata()
        let rightElevonPosition = rightElevonMeshMetadata.initialPositionInParentMesh - newElevonOrigin
        rightElevon.setPosition(rightElevonPosition)
        addChild(rightElevon)
        
        // Set flaps as children:
        let leftFlapMeshMetadata = leftFlap.getSubmeshVertexMetadata()
        let leftFlapPosition = leftFlapMeshMetadata.initialPositionInParentMesh - newFlapsOrigin
        leftFlap.setPosition(leftFlapPosition)
        addChild(leftFlap)
        
        let rightFlapMeshMetadata = rightFlap.getSubmeshVertexMetadata()
        let rightFlapPosition = rightFlapMeshMetadata.initialPositionInParentMesh - newFlapsOrigin
        rightFlap.setPosition(rightFlapPosition)
        addChild(rightFlap)
    }
    
    func weaponReleaseSetup(submeshGameObject: SubMeshGameObject) {
        let releasePosition = submeshGameObject.getPosition() + submeshGameObject.getInitialPositionInParentMesh()
        let rotatedPosition = (self.rotationMatrix * float4(releasePosition, 1)).xyz
        submeshGameObject.setPosition(rotatedPosition + self.getPosition())
        submeshGameObject.rotationMatrix = self.rotationMatrix
        submeshGameObject.setScale(self.getScale())
    }
    
    func weaponRelease(store: Store, handleBlock: (String) -> Void) {
        if store.remaining > 0 {
            let storeIdx = store.submeshNames.count - store.remaining
            let storeToRelease = store.submeshNames[storeIdx]
            print("Store to release: \(storeToRelease)")
            handleBlock(storeToRelease)
            store.remaining -= 1
            submeshesToDisplay[storeToRelease] = false
        }
    }
    
    override func doUpdate() {
        if shouldUpdate {
            super.doUpdate()
        }
        
        InputManager.HasDiscreteCommandDebounced(command: .FireMissileAIM9) {
            let aim9s = stores[F18.AIM9Name]!
            weaponRelease(store: aim9s) { storeToRelease in
                print("Fox 2!")
                let sidewinder = Sidewinder(modelName: F18.F18_ModelName, submeshName: storeToRelease)
                sidewinder.fire(direction: self.getFwdVector(), speed: 0.5)
                weaponReleaseSetup(submeshGameObject: sidewinder)
                self.parent!.addChild(sidewinder)
            }
        }
        
        InputManager.HasDiscreteCommandDebounced(command: .FireMissileAIM120) {
            let aim120s = stores[F18.AIM120Name]!
            weaponRelease(store: aim120s) { storeToRelease in
                print("Fox 3!")
                let amraam = AIM120(modelName: F18.F18_ModelName, submeshName: storeToRelease)
                amraam.fire(direction: self.getFwdVector(), speed: 0.5)
                weaponReleaseSetup(submeshGameObject: amraam)
                self.parent!.addChild(amraam)
            }
        }
        
        InputManager.HasDiscreteCommandDebounced(command: .DropBomb) {
            let gbu16s = stores[F18.GBU16Name]!
            weaponRelease(store: gbu16s) { storeToRelease in
                print("Dropping JDAM!")
                let jdam = GBU16(modelName: F18.F18_ModelName, submeshName: storeToRelease)
                jdam.drop(forwardComponent: 0.02)
                weaponReleaseSetup(submeshGameObject: jdam)
                self.parent!.addChild(jdam)
            }
        }
        
        InputManager.HasDiscreteCommandDebounced(command: .JettisonFuelTank) {
            let fuelTanks = stores[F18.FuelTankName]!
            weaponRelease(store: fuelTanks) { storeToRelease in
                print("Jettisoning fuel tank!")
                let fuelTank = FuelTank(modelName: F18.F18_ModelName, submeshName: storeToRelease)
                fuelTank.drop(forwardComponent: 0.0)
                weaponReleaseSetup(submeshGameObject: fuelTank)
                self.parent!.addChild(fuelTank)
            }
        }
        
        if InputManager.DiscreteCommand(.ResetLoadout) {
            // Reset loadout
            for storeName in F18.storesNames {
                let store = stores[storeName]!
                if store.remaining < store.submeshNames.count {
                    store.remaining = store.submeshNames.count
                    for smn in store.submeshNames {
                        submeshesToDisplay[smn] = true
                    }
                }
            }
        }
        
        let roll = InputManager.ContinuousCommand(.Roll)
        leftAileron.setRotation(angle: -roll, axis: leftWingRearControlSurfaceRotationAxis)
        rightAileron.setRotation(angle: -roll, axis: rightWingRearControlSurfaceRotationAxis)
        
        let pitch = InputManager.ContinuousCommand(.Pitch)
        
        // TODO: This results in really wonky visuals:
//        leftElevon.setRotationX(-pitch)
//        rightElevon.setRotationX(-pitch)
        
        leftElevon.setRotation(angle: -pitch, axis: X_AXIS)
        rightElevon.setRotation(angle: -pitch, axis: X_AXIS)
        
        InputManager.HasDiscreteCommandDebounced(command: .ToggleFlaps) {
            if !flapsDeployed {
                flapsBeganExtending = true
            } else {
                flapsBeganRetracting = true
            }
        }
        
        
        if flapsBeganExtending {
            if flapsDegrees < 30.0 {
                flapsDegrees += 1.0
                leftFlap.setRotation(angle: -Float(flapsDegrees).toRadians, axis: leftWingRearControlSurfaceRotationAxis)
                rightFlap.setRotation(angle: Float(flapsDegrees).toRadians, axis: rightWingRearControlSurfaceRotationAxis)
            } else {
                flapsFinishedExtending = true
            }
        }
        
        if flapsBeganRetracting {
            if flapsDegrees > 0.0 {
                flapsDegrees -= 1.0
                leftFlap.setRotation(angle: -Float(flapsDegrees).toRadians, axis: leftWingRearControlSurfaceRotationAxis)
                rightFlap.setRotation(angle: Float(flapsDegrees).toRadians, axis: rightWingRearControlSurfaceRotationAxis)
            } else {
                flapsFinishedRetracting = true
            }
        }
        
        if flapsFinishedExtending || flapsFinishedRetracting {
            flapsDeployed.toggle()
            flapsBeganExtending = false
            flapsFinishedExtending = false
            flapsBeganRetracting = false
            flapsFinishedRetracting = false
        }
        
        // TODO: Perhaps extract this out to general function:
        InputManager.HasDiscreteCommandDebounced(command: .ToggleGear) {
            if !landingGearDeployed {
                landingGearBeganExtending = true
            } else {
                landingGearBeganRetracting = true
            }
        }
        
        if landingGearBeganExtending {
            if landingGearDegrees > 0.0 {
                landingGearDegrees -= 1.0
                // TODO
            }
        } else {
            landingGearFinishedExtending = true
        }
        
        if landingGearBeganRetracting {
            if landingGearDegrees < 90.0 {
                landingGearDegrees += 1.0
                // TODO
            }
        } else {
            landingGearFinishedRetracting = true
        }
        
        if landingGearFinishedExtending || landingGearFinishedRetracting {
            landingGearDeployed.toggle()
            landingGearBeganExtending = false
            landingGearFinishedExtending = false
            landingGearBeganRetracting = false
            landingGearFinishedRetracting = false
        }
    }
    
    override func doRender(_ renderEncoder: MTLRenderCommandEncoder,
                           applyMaterials: Bool = true,
                           submeshesToRender: [String : Bool]? = nil) {
//        super.doRender(renderCommandEncoder, applyMaterials: applyMaterials, submeshesToRender: submeshesToDisplay)
        super.doRender(renderEncoder, applyMaterials: applyMaterials)
    }
    
    override func doRenderShadow(_ renderEncoder: MTLRenderCommandEncoder, submeshesToRender: [String : Bool]?) {
//        super.doRenderShadow(renderCommandEncoder, submeshesToRender: submeshesToDisplay)
        super.doRenderShadow(renderEncoder)
    }
}
