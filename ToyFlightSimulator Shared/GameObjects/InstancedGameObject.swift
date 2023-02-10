//
//  InstancedGameObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/22.
//

import MetalKit

class InstancedGameObject: Node {
    private var _material = Material()
    private var _mesh: Mesh!
    internal var _nodes: [Node] = []
    
    private var _modelConstantBuffer: MTLBuffer!
    
    init(meshType: MeshType, instanceCount: Int) {
        super.init(name: "Instanced Game Object")
        self._renderPipelineStateType = .Instanced
        self._mesh = Assets.Meshes[meshType]
        self._mesh.setInstanceCount(instanceCount)
        self.generateInstances(instanceCount)
        self.createBuffers(instanceCount)
    }
    
    func updateNodes(_ updateNodeFunction: (Node, Int) -> ()) {
        for (index, node) in _nodes.enumerated() {
            updateNodeFunction(node, index)
        }
    }
    
    func generateInstances(_ instanceCount: Int) {
        for _ in 0..<instanceCount {
            _nodes.append(Node(name: "\(getName())_InstancedNode"))
        }
    }
    
    func createBuffers(_ instanceCount: Int) {
        _modelConstantBuffer = Engine.Device.makeBuffer(length: ModelConstants.stride(instanceCount),
                                                        options: [])
    }
    
    override func update() {
        var pointer = _modelConstantBuffer.contents().bindMemory(to: ModelConstants.self, capacity: _nodes.count)
        for node in _nodes {
            pointer.pointee.modelMatrix = matrix_multiply(self.modelMatrix, node.modelMatrix)
            pointer = pointer.advanced(by: 1)
        }
        super.update()
    }
}

extension InstancedGameObject: Renderable {
    func doRender(_ renderCommandEncoder: MTLRenderCommandEncoder) {
        renderCommandEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Instanced])
        renderCommandEncoder.setDepthStencilState(Graphics.DepthStencilStates[.Less])
        
        // Vertex Shader
        renderCommandEncoder.setVertexBuffer(_modelConstantBuffer, offset: 0, index: 2)
        
        // Fragment Shader
        renderCommandEncoder.setFragmentBytes(&_material, length: Material.stride, index: 1)
        
        _mesh.drawPrimitives(renderCommandEncoder)
    }
    
    func doRenderShadow(_ renderCommandEncoder: MTLRenderCommandEncoder) {
        // NOT IMPLEMENTED
        fatalError("NOT IMPLEMENTED")
    }
}

// Material Properties
extension InstancedGameObject {
    public func setColor(_ color: SIMD4<Float>) {
        self._material.color = color
    }
}
