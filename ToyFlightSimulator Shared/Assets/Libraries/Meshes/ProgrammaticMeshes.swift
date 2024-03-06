//
//  ProgrammaticMeshes.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/5/24.
//

class TriangleMesh: Mesh {
    override func createMesh() {
        addVertex(position: float3( 0, 1,0), color: float4(1,0,0,1), textureCoordinate: float2(0.5,0.0), normal: float3(0,0,1))
        addVertex(position: float3(-1,-1,0), color: float4(0,1,0,1), textureCoordinate: float2(0.0,1.0), normal: float3(0,0,1))
        addVertex(position: float3( 1,-1,0), color: float4(0,0,1,1), textureCoordinate: float2(1.0,1.0), normal: float3(0,0,1))
    }
}

class QuadMesh: Mesh {
    override func createMesh() {
        addVertex(position: float3( 1, 1,0),
                  color: float4(1,0,0,1),
                  textureCoordinate: float2(1,0),
                  normal: float3(0,0,1)) //Top Right
        addVertex(position: float3(-1, 1,0),
                  color: float4(0,1,0,1),
                  textureCoordinate: float2(0,0),
                  normal: float3(0,0,1)) //Top Left
        addVertex(position: float3(-1,-1,0),
                  color: float4(0,0,1,1),
                  textureCoordinate: float2(0,1),
                  normal: float3(0,0,1)) //Bottom Left
        addVertex(position: float3( 1,-1,0),
                  color: float4(1,0,1,1),
                  textureCoordinate: float2(1,1),
                  normal: float3(0,0,1)) //Bottom Right
        
        addSubmesh(Submesh(indices: [
            0,1,2,
            0,2,3
        ]))
    }
}

class CubeMesh: Mesh {
    override func createMesh() {
        //Left
        addVertex(position: float3(-1.0,-1.0,-1.0),
                  color: float4(1.0, 0.5, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3(-1, 0, 0))
        addVertex(position: float3(-1.0,-1.0, 1.0),
                  color: float4(0.0, 1.0, 0.5, 1.0),
                  textureCoordinate: float2(0,0),
                  normal: float3(-1, 0, 0))
        addVertex(position: float3(-1.0, 1.0, 1.0),
                  color: float4(0.0, 0.5, 1.0, 1.0),
                  textureCoordinate: float2(0,1),
                  normal: float3(-1, 0, 0))
        addVertex(position: float3(-1.0,-1.0,-1.0),
                  color: float4(1.0, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(1,1),
                  normal: float3(-1, 0, 0))
        addVertex(position: float3(-1.0, 1.0, 1.0),
                  color: float4(0.0, 1.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3(-1, 0, 0))
        addVertex(position: float3(-1.0, 1.0,-1.0),
                  color: float4(1.0, 0.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3(-1, 0, 0))
        
        //RIGHT
        addVertex(position: float3( 1.0, 1.0, 1.0),
                  color: float4(1.0, 0.0, 0.5, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 1, 0, 0))
        addVertex(position: float3( 1.0,-1.0,-1.0),
                  color: float4(0.0, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 1, 0, 0))
        addVertex(position: float3( 1.0, 1.0,-1.0),
                  color: float4(0.0, 0.5, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 1, 0, 0))
        addVertex(position: float3( 1.0,-1.0,-1.0),
                  color: float4(1.0, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 1, 0, 0))
        addVertex(position: float3( 1.0, 1.0, 1.0),
                  color: float4(0.0, 1.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 1, 0, 0))
        addVertex(position: float3( 1.0,-1.0, 1.0),
                  color: float4(1.0, 0.5, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 1, 0, 0))
        
        //TOP
        addVertex(position: float3( 1.0, 1.0, 1.0),
                  color: float4(1.0, 0.0, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 1, 0))
        addVertex(position: float3( 1.0, 1.0,-1.0),
                  color: float4(0.0, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(0,0),
                  normal: float3( 0, 1, 0))
        addVertex(position: float3(-1.0, 1.0,-1.0),
                  color: float4(0.0, 0.0, 1.0, 1.0),
                  textureCoordinate: float2(0,1),
                  normal: float3( 0, 1, 0))
        addVertex(position: float3( 1.0, 1.0, 1.0),
                  color: float4(1.0, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(1,1),
                  normal: float3( 0, 1, 0))
        addVertex(position: float3(-1.0, 1.0,-1.0),
                  color: float4(0.5, 1.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 1, 0))
        addVertex(position: float3(-1.0, 1.0, 1.0),
                  color: float4(1.0, 0.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 1, 0))
        
//        addSubmesh(Submesh(indices: [
//            0,1,2,
//            0,2,3
//        ]))
        
        //BOTTOM
        addVertex(position: float3( 1.0,-1.0, 1.0),
                  color: float4(1.0, 0.5, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0,-1, 0))
        addVertex(position: float3(-1.0,-1.0,-1.0),
                  color: float4(0.5, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0,-1, 0))
        addVertex(position: float3( 1.0,-1.0,-1.0),
                  color: float4(0.0, 0.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0,-1, 0))
        addVertex(position: float3( 1.0,-1.0, 1.0),
                  color: float4(1.0, 1.0, 0.5, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0,-1, 0))
        addVertex(position: float3(-1.0,-1.0, 1.0),
                  color: float4(0.0, 1.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0,-1, 0))
        addVertex(position: float3(-1.0,-1.0,-1.0),
                  color: float4(1.0, 0.5, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0,-1, 0))
        
        //BACK
        addVertex(position: float3( 1.0, 1.0,-1.0),
                  color: float4(1.0, 0.5, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 0,-1))
        addVertex(position: float3(-1.0,-1.0,-1.0),
                  color: float4(0.5, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 0,-1))
        addVertex(position: float3(-1.0, 1.0,-1.0),
                  color: float4(0.0, 0.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 0,-1))
        addVertex(position: float3( 1.0, 1.0,-1.0),
                  color: float4(1.0, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 0,-1))
        addVertex(position: float3( 1.0,-1.0,-1.0),
                  color: float4(0.0, 1.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 0,-1))
        addVertex(position: float3(-1.0,-1.0,-1.0),
                  color: float4(1.0,0.5,1.0,1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3(0,0,-1))
        
        //FRONT
        addVertex(position: float3(-1.0, 1.0, 1.0),
                  color: float4(1.0, 0.5, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 0, 1))
        addVertex(position: float3(-1.0,-1.0, 1.0),
                  color: float4(0.0, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(0,0),
                  normal: float3( 0, 0, 1))
        addVertex(position: float3( 1.0,-1.0, 1.0),
                  color: float4(0.5, 0.0, 1.0, 1.0),
                  textureCoordinate: float2(0,1),
                  normal: float3( 0, 0, 1))
        addVertex(position: float3( 1.0, 1.0, 1.0),
                  color: float4(1.0, 1.0, 0.5, 1.0),
                  textureCoordinate: float2(1,1),
                  normal: float3( 0, 0, 1))
        addVertex(position: float3(-1.0, 1.0, 1.0),
                  color: float4(0.0, 1.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 0, 1))
        addVertex(position: float3( 1.0,-1.0, 1.0),
                  color: float4(1.0, 0.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 0, 1))
    }
}

