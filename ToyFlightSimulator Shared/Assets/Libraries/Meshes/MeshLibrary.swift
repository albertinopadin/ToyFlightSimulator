//
//  MeshLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit

enum MeshType {
    case None
    case Triangle_Custom
    case Quad_Custom
    case Cube_Custom
    case Sphere_Custom
    case Capsule_Custom
    
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

class MeshLibrary: Library<MeshType, Mesh> {
    private var _library: [MeshType: Mesh] = [:]
    
    override func makeLibrary() {
        _library.updateValue(NoMesh(), forKey: .None)
        _library.updateValue(TriangleMesh(), forKey: .Triangle_Custom)
        _library.updateValue(QuadMesh(), forKey: .Quad_Custom)
        _library.updateValue(CubeMesh(), forKey: .Cube_Custom)
        _library.updateValue(SphereMesh(), forKey: .Sphere_Custom)
        _library.updateValue(CapsuleMesh(), forKey: .Capsule_Custom)
        _library.updateValue(SkyboxMesh(), forKey: .Skybox)
        
        _library.updateValue(ObjMesh("sphere"), forKey: .Sphere)
        _library.updateValue(ObjMesh("quad"), forKey: .Quad)
        _library.updateValue(ObjMesh("skysphere"), forKey: .SkySphere)
        
        _library.updateValue(ObjMesh("f16r"), forKey: .F16)
        _library.updateValue(ObjMesh("FA-18F"), forKey: .F18)
        
        _library.updateValue(UsdMesh("FA-18F"), forKey: .RC_F18)
//        _library.updateValue(UsdMesh("F35_JSF", fileExtension: .USDC), forKey: .CGTrader_F35)
        _library.updateValue(UsdMesh("F-35A_Lightning_II"), forKey: .Sketchfab_F35)
        _library.updateValue(UsdMesh("F-22_Raptor"), forKey: .Sketchfab_F22)
        
        _library.updateValue(PlaneMesh(), forKey: .Plane)
        _library.updateValue(IcosahedronMesh(), forKey: .Icosahedron)
        _library.updateValue(ObjMesh("Temple"), forKey: .Temple)
    }
    
    override subscript(type: MeshType) -> Mesh {
        return _library[type]!
    }
}
