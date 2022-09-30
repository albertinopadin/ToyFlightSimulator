//
//  GameController.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/27/22.
//

//import Metal
//import MetalKit
//
//
//class SimulationController {
//    var renderer: Renderer!
//    private var mtkMeshBufferAllocator: MTKMeshBufferAllocator!
//    
//    init(view: MTKView, device: MTLDevice) {
//        var gameVertexDescriptor = GameVertexDescriptor()
//        gameVertexDescriptor.addAttribute(name: MDLVertexAttributePosition, format: .float3)
//        gameVertexDescriptor.addAttribute(name: MDLVertexAttributeNormal, format: .float3)
//        
//        renderer = Renderer(device: device, view: view, gameVertexDescriptor: gameVertexDescriptor)
//        mtkMeshBufferAllocator = MTKMeshBufferAllocator(device: device)
//        
//        let sphereMesh = makeSphereMesh(size: 1.0,
//                                        device: device,
//                                        vertexDescriptor: gameVertexDescriptor.mdlVertexDescriptor,
//                                        allocator: mtkMeshBufferAllocator)
//        let sphereNode = Node(mesh: sphereMesh)
//        sphereNode.color = BLUE_COLOR
//        renderer.appendNode(sphereNode)
//    }
//}
