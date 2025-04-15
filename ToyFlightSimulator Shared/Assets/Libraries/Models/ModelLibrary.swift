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
        _library.updateValue(UsdModel("F-35A_Lightning_II"), forKey: .Sketchfab_F35)
        _library.updateValue(UsdModel("F-22_Raptor"), forKey: .Sketchfab_F22)
        
        _library.updateValue(Model(name: "Plane", mesh: PlaneMesh()), forKey: .Plane)
        _library.updateValue(Model(name: "Icosahedron", mesh: IcosahedronMesh()), forKey: .Icosahedron)
        _library.updateValue(ObjModel("Temple"), forKey: .Temple)
    }
    
    override subscript(type: ModelType) -> Model {
        return _library[type]!
    }
}
