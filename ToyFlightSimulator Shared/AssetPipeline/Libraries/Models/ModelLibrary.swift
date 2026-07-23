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

final class ModelLibrary: LazyLibrary<ModelType, Model>, @unchecked Sendable {
    override func makeLibrary() {
        let rotate180AroundY = Transform.rotationMatrix(radians: Float(180).toRadians, axis: Y_AXIS)

        register(.None)     { Model(name: "No Mesh", mesh: NoMesh()) }
        register(.Triangle) { Model(name: "Triangle", mesh: ProgrammaticTriangleMesh()) }
        register(.Cube)     { Model(name: "Cube", mesh: CubeMesh()) }
        register(.Capsule)  { Model(name: "Capsule", mesh: CapsuleMesh()) }
        register(.Skybox)   { Model(name: "Skybox", mesh: SkyboxMesh()) }

        register(.Sphere)    { ObjModel("sphere") }
        register(.Quad)      { ObjModel("quad") }
        register(.SkySphere) { ObjModel("skysphere") }

        // realWorldLength (meters, nose-to-tail) drives import-time meterization — see
        // Model.init and plans/claude/meter_scale_implementation_plan_2026-07-23.md.
        // OBJ has no unit metadata; F-16C native length 2.253.
        register(.F16) { ObjModel("f16r", basisTransform: rotate180AroundY, realWorldLength: 15.06) }
        // F18: native units are already meters (measured 18.267 vs 18.31 real, −0.2%), so it is
        // deliberately NOT meterized: SingleSubmeshMeshLibrary extracts its weapons and control
        // surfaces through a path that bypasses Model.init, and skipping both keeps the fuselage
        // and the extracted parts exactly congruent.
        register(.F18) { ObjModel("FA-18F", basisTransform: rotate180AroundY) }

//        register(.RC_F18) { UsdModel("FA-18F") }

        // Declared MPU=1 (m) would give 8.6 m — 46% of real; native length 8.615 on Y.
        register(.CGTrader_F22) {
            UsdModel("cgtrader_F22",
                     fileExtension: .USDZ,
                     basisTransform: Transform.transformXMinusZYToXYZ,
                     realWorldLength: 18.92)
        }

        // Declared MPU=0.01 (cm) would give 4.34 m — 28% of real; native length 433.6 on Z (no basis needed).
        register(.Sketchfab_F35) { UsdModel("F-35A_Lightning_II", realWorldLength: 15.67) }

        // Declared MPU=0.01 (cm) would give 10.98 m — 58% of real; native length 1098.2 on X.
        register(.Sketchfab_F22) {
            UsdModel("F-22_Raptor", basisTransform: Transform.transformYMinusZXToXYZ, realWorldLength: 18.92)
        }

        register(.Plane)       { Model(name: "Plane", mesh: PlaneMesh()) }
        register(.Icosahedron) { Model(name: "Icosahedron", mesh: IcosahedronMesh()) }
        register(.Temple)      { ObjModel("Temple") }

        // -----------------------------------

        register(.F18_Sidewinder_Left) {
            Model(name: "F18_AIM9_Left", mesh: Assets.SingleSMMeshes[.F18_Sidewinder_Left])
        }
        register(.F18_AIM120_Left) {
            Model(name: "F18_AIM120_Left", mesh: Assets.SingleSMMeshes[.F18_AIM120_Left])
        }
        register(.F18_GBU16_Left) {
            Model(name: "F18_GBU16_Left", mesh: Assets.SingleSMMeshes[.F18_GBU16_Left])
        }

        register(.F18_Sidewinder_Right) {
            Model(name: "F18_AIM9_Right", mesh: Assets.SingleSMMeshes[.F18_Sidewinder_Right])
        }
        register(.F18_AIM120_Right) {
            Model(name: "F18_AIM120_Right", mesh: Assets.SingleSMMeshes[.F18_AIM120_Right])
        }
        register(.F18_GBU16_Right) {
            Model(name: "F18_GBU16_Right", mesh: Assets.SingleSMMeshes[.F18_GBU16_Right])
        }

        register(.F18_FuelTank_Left) {
            Model(name: "F18_FuelTank_Left", mesh: Assets.SingleSMMeshes[.F18_FuelTank_Left])
        }
        register(.F18_FuelTank_Center) {
            Model(name: "F18_FuelTank_Center", mesh: Assets.SingleSMMeshes[.F18_FuelTank_Center])
        }
        register(.F18_FuelTank_Right) {
            Model(name: "F18_FuelTank_Right", mesh: Assets.SingleSMMeshes[.F18_FuelTank_Right])
        }

        register(.F18_Aileron_Left)  { Model(name: "F18_Aileron_Left",  mesh: Assets.SingleSMMeshes[.F18_Aileron_Left]) }
        register(.F18_Aileron_Right) { Model(name: "F18_Aileron_Right", mesh: Assets.SingleSMMeshes[.F18_Aileron_Right]) }
        register(.F18_Elevon_Left)   { Model(name: "F18_Elevon_Left",   mesh: Assets.SingleSMMeshes[.F18_Elevon_Left]) }
        register(.F18_Elevon_Right)  { Model(name: "F18_Elevon_Right",  mesh: Assets.SingleSMMeshes[.F18_Elevon_Right]) }
        register(.F18_Flap_Left)     { Model(name: "F18_Flap_Left",     mesh: Assets.SingleSMMeshes[.F18_Flap_Left]) }
        register(.F18_Flap_Right)    { Model(name: "F18_Flap_Right",    mesh: Assets.SingleSMMeshes[.F18_Flap_Right]) }
        register(.F18_Rudder_Left)   { Model(name: "F18_Rudder_Left",   mesh: Assets.SingleSMMeshes[.F18_Rudder_Left]) }
        register(.F18_Rudder_Right)  { Model(name: "F18_Rudder_Right",  mesh: Assets.SingleSMMeshes[.F18_Rudder_Right]) }
    }

    override subscript(type: ModelType) -> Model {
        guard let model = resolve(type) else {
            fatalError("[ModelLibrary] No model factory registered for type: \(type)")
        }
        return model
    }
}
