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
    
    case Plane
    case Icosahedron
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
        _library.updateValue(PlaneMesh(), forKey: .Plane)
        _library.updateValue(IcosahedronMesh(), forKey: .Icosahedron)
    }
    
    override subscript(type: MeshType) -> Mesh {
        return _library[type]!
    }
}
