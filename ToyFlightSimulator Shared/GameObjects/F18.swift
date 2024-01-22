//
//  F18.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 2/11/23.
//

import MetalKit

class Store {
    var remaining: Int
    var submeshNames: [String]

    init(remaining: Int, submeshNames: [String]) {
        self.remaining = remaining
        self.submeshNames = submeshNames
    }
}

class F18: Aircraft {
    private var _spacePressed: Bool = false
    private var _mKeyPressed: Bool = false
    private var _nKeyPressed: Bool = false
    private var _jKeyPressed: Bool = false
    
    static let F18_ModelName = "FA-18F"
    
    static let AIM9Name = "AIM-9"
    static let AIM120Name = "AIM-120"
    static let GBU16Name = "GBU-16"
    static let FuelTankName = "FuelTank"
    static let NoseGearName = "NoseWheels_Paint"
    
    static let storesNames = [
        AIM9Name,
        AIM120Name,
        GBU16Name,
        FuelTankName
    ]
    
    let stores: [String: Store] = [
        AIM9Name: Store(remaining: 2, submeshNames: ["AIM-9XL_Paint", "AIM-9XR_Paint"]),
        AIM120Name: Store(remaining: 2, submeshNames: ["AIM-120DL_Paint", "AIM-120DR_Paint"]),
        GBU16Name: Store(remaining: 2, submeshNames: ["GBU-16L_Paint", "GBU-16R_Paint"]),
        FuelTankName: Store(remaining: 3, submeshNames: ["TankWingL_Paint", "TankWingR_Paint", "TankCenter_Paint"])
    ]
    
    
//    var landingGear: [String] = [
//
//    ]
    
    let noseWheelGearSubmeshNames: [String] = [
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
        "NoseWheels_Paint"
    ]
    
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
        "ElevatorL_Paint": false,   // L Elevon
        "ElevatorR_Paint": false,   // R Elevon
        "RudderL_Paint": false,     // L Rudder
        "RudderR_Paint": false,     // R Rudder
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
        "FlapsL_Paint": false,      // L Flap
        "FlapsR_Paint": false,      // R Flap
        "EleronsL_Paint": false,    // L Aileron
        "EleronsR_Paint": false,    // R Aileron
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
        "TopStrut_Paint": true,  // TODO:: Need to rotate all of this to hide front gear...
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
    
    let leftRudder = SubMeshGameObject(name: "Left_Rudder",
                                           modelName: F18_ModelName,
                                           submeshName: "RudderL_Paint",
                                           renderPipelineStateType: .OpaqueMaterial)

    let rightRudder = SubMeshGameObject(name: "Right_Rudder",
                                        modelName: F18_ModelName,
                                        submeshName: "RudderR_Paint",
                                        renderPipelineStateType: .OpaqueMaterial)
    
    var flapsDeployed: Bool = false
    var flapsDegrees: Float = 0.0
    var flapsBeganExtending: Bool = false
    var flapsFinishedExtending: Bool = false
    var flapsBeganRetracting: Bool = false
    var flapsFinishedRetracting: Bool = false
    
    let leftWingRearControlSurfaceRotationAxis = float3(-1, 0, 0.15)
    let rightWingRearControlSurfaceRotationAxis = float3(1, 0, 0.15)
    
    let leftRudderControlSurfaceRotationAxis = normalize(float3(-0.25, 0.8, 0.30))
    let rightRudderControlSurfaceRotationAxis = normalize(float3(0.25, 0.8, 0.30))
    
    var landingGearDeployed: Bool = false
    var landingGearDegrees: Float = 0.0
    var landingGearBeganExtending: Bool = false
    var landingGearFinishedExtending: Bool = false
    var landingGearBeganRetracting: Bool = false
    var landingGearFinishedRetracting: Bool = false
    
    init(scale: Float = 1.0, shouldUpdate: Bool = true) {
        super.init(name: "F-18",
                   meshType: .F18,
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
        
        // Rudders:
        let newRuddersOrigin = float3(0, 0, 0.25)
        leftRudder.setSubmeshOrigin(newRuddersOrigin)
        rightRudder.setSubmeshOrigin(newRuddersOrigin)
        
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
        
        // Set rudders as children:
        let leftRudderMeshMetadata = leftRudder.getSubmeshVertexMetadata()
        let leftRudderPosition = leftRudderMeshMetadata.initialPositionInParentMesh - newRuddersOrigin
        leftRudder.setPosition(leftRudderPosition)
        addChild(leftRudder)

        let rightRudderMeshMetadata = rightRudder.getSubmeshVertexMetadata()
        let rightRudderPosition = rightRudderMeshMetadata.initialPositionInParentMesh - newRuddersOrigin
        rightRudder.setPosition(rightRudderPosition)
        addChild(rightRudder)
    }
    
    func weaponReleaseSetup(with node: Node, submeshGameObject: SubMeshGameObject) {
        let releasePosition = submeshGameObject.getPosition() + submeshGameObject.getInitialPositionInParentMesh()
        let rotatedPosition = (node.rotationMatrix * float4(releasePosition, 1)).xyz
        submeshGameObject.setPosition(rotatedPosition + node.getPosition())
        submeshGameObject.rotationMatrix = node.rotationMatrix
        submeshGameObject.setScale(node.getScale())
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
        
        self.checkControlCommands()
        
        if let containerNode {
            self.checkStoresCommands(with: containerNode)
        } else {
            self.checkStoresCommands(with: self)
        }
        
        // Extract this out into own method:
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
        
        // TODO: Figure out how to move individual submesh without re-instantiating it:
//        InputManager.HasDiscreteCommandDebounced(command: .ToggleGear) {
//            print("Toggling gear \(gearDown ? "up": "down")")
//
//            for noseGearSubmeshName in noseWheelGearSubmeshNames {
//                if let submesh = self._mesh._childMeshes.map({
//                    $0._submeshes.filter({ $0.name == noseGearSubmeshName })
//                }).first?.first {
//                    print("Found \(noseGearSubmeshName)")
//                    if gearDown {
////                        submesh.submeshConstants.submeshModelMatrix = Transform.rotationMatrix(radians: Float(1.0).toRadians,
////                                                                                               axis: X_AXIS)
//                        submesh.submeshConstants.submeshModelMatrix = simd_float4x4(simd_quatf(angle: Float(-10.0).toRadians,
//                                                                                               axis: getRightVector()))
//
//                    } else {
////                        submesh.submeshConstants.submeshModelMatrix = Transform.rotationMatrix(radians: Float(-1.0).toRadians,
////                                                                                               axis: X_AXIS)
//                        submesh.submeshConstants.submeshModelMatrix = matrix_identity_float4x4
//                    }
//                }
//            }
//
//            gearDown.toggle()
//        }
        
        
//        let noseGearRotation = simd_float4x4(simd_quatf(angle: Float(-0.25).toRadians, axis: getRightVector()))
//        let noseGearRotation = simd_float4x4(simd_quatf(angle: Float(-0.5).toRadians, axis: X_AXIS))
//        let noseGearTranslationToOrigin = Transform.translationMatrix(-self.getPosition())
//        let noseGearTranslationBack = Transform.translationMatrix(self.getPosition())
        

//        for noseGearSubmeshName in noseWheelGearSubmeshNames {
//            if let submesh = self._mesh._childMeshes.map({
//                $0._submeshes.filter({ $0.name == noseGearSubmeshName })
//            }).first?.first {
////                if appliedTranslation {
////                    submesh.submeshConstants.submeshModelMatrix = noseGearRotation * submesh.submeshConstants.submeshModelMatrix
////                } else {
////                    submesh.submeshConstants.submeshModelMatrix = noseGearTranslation * noseGearRotation * submesh.submeshConstants.submeshModelMatrix
////                }
//
////                submesh.submeshConstants.submeshModelMatrix = submesh.submeshConstants.submeshModelMatrix * noseGearRotation
//
////                submesh.submeshConstants.submeshModelMatrix = noseGearTranslationBack * noseGearRotation * noseGearTranslationToOrigin * submesh.submeshConstants.submeshModelMatrix
//
//                submesh.submeshConstants.submeshModelMatrix = noseGearRotation * submesh.submeshConstants.submeshModelMatrix
//            }
//        }
//
//        appliedTranslation = true
        
    }
    
    private func checkControlCommands() {
        let roll = InputManager.ContinuousCommand(.Roll)
        leftAileron.setRotation(angle: -roll, axis: leftWingRearControlSurfaceRotationAxis)
        rightAileron.setRotation(angle: -roll, axis: rightWingRearControlSurfaceRotationAxis)
        
        let pitch = InputManager.ContinuousCommand(.Pitch)
        leftElevon.setRotation(angle: -pitch, axis: X_AXIS)
        rightElevon.setRotation(angle: -pitch, axis: X_AXIS)
        
        // TODO: This results in really wonky visuals:
//        leftElevon.setRotationX(-pitch)
//        rightElevon.setRotationX(-pitch)
        
        let yaw = InputManager.ContinuousCommand(.Yaw)
        leftRudder.setRotation(angle: -yaw, axis: leftRudderControlSurfaceRotationAxis)
        rightRudder.setRotation(angle: -yaw, axis: rightRudderControlSurfaceRotationAxis)
    }
    
    private func checkStoresCommands(with node: Node) {
        InputManager.HasDiscreteCommandDebounced(command: .FireMissileAIM9) {
            let aim9s = stores[F18.AIM9Name]!
            weaponRelease(store: aim9s) { storeToRelease in
                print("Fox 2!")
                let sidewinder = Sidewinder(modelName: F18.F18_ModelName, submeshName: storeToRelease)
                sidewinder.fire(direction: node.getFwdVector(), speed: 0.5)
                weaponReleaseSetup(with: node, submeshGameObject: sidewinder)
                node.parent!.addChild(sidewinder)
            }
        }
        
        InputManager.HasDiscreteCommandDebounced(command: .FireMissileAIM120) {
            let aim120s = stores[F18.AIM120Name]!
            weaponRelease(store: aim120s) { storeToRelease in
                print("Fox 3!")
                let amraam = AIM120(modelName: F18.F18_ModelName, submeshName: storeToRelease)
                amraam.fire(direction: node.getFwdVector(), speed: 0.5)
                weaponReleaseSetup(with: node, submeshGameObject: amraam)
                node.parent!.addChild(amraam)
            }
        }
        
        InputManager.HasDiscreteCommandDebounced(command: .DropBomb) {
            let gbu16s = stores[F18.GBU16Name]!
            weaponRelease(store: gbu16s) { storeToRelease in
                print("Dropping JDAM!")
                let jdam = GBU16(modelName: F18.F18_ModelName, submeshName: storeToRelease)
                jdam.drop(forwardComponent: 0.02)
                weaponReleaseSetup(with: node, submeshGameObject: jdam)
                node.parent!.addChild(jdam)
            }
        }
        
        InputManager.HasDiscreteCommandDebounced(command: .JettisonFuelTank) {
            let fuelTanks = stores[F18.FuelTankName]!
            weaponRelease(store: fuelTanks) { storeToRelease in
                print("Jettisoning fuel tank!")
                let fuelTank = FuelTank(modelName: F18.F18_ModelName, submeshName: storeToRelease)
                fuelTank.drop(forwardComponent: 0.0)
                weaponReleaseSetup(with: node, submeshGameObject: fuelTank)
                node.parent!.addChild(fuelTank)
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
