//
//  InstancedGameObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/22.
//

import MetalKit

class InstancedGameObject: Node {
    public var model: Model!
    
    private var _material: MaterialProperties?
    internal var _nodes: [Node] = []
    
    private var _modelConstantBuffer: MTLBuffer!
    
    init(modelType: ModelType, instanceCount: Int) {
        super.init(name: "Instanced Game Object")
        self.model = Assets.Models[modelType]
        self.model.meshes.forEach { $0.setInstanceCount(instanceCount) }
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
        super.update()
        var pointer = _modelConstantBuffer.contents().bindMemory(to: ModelConstants.self, capacity: _nodes.count)
        for node in _nodes {
            pointer.pointee.modelMatrix = matrix_multiply(self.modelMatrix, node.modelMatrix)
            pointer = pointer.advanced(by: 1)
        }
    }
}

// TODO: Implement instancing in DrawManager
//extension InstancedGameObject: Renderable {
//    func doRender(_ renderEncoder: MTLRenderCommandEncoder,
//                  applyMaterials: Bool = true,
//                  submeshesToRender: [String: Bool]? = nil) {
//        renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Instanced])
//        renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.Less])
//        
//        // Vertex Shader
//        renderEncoder.setVertexBuffer(_modelConstantBuffer, offset: 0, index: 2)
//        
//        // Fragment Shader
//        renderEncoder.setFragmentBytes(&_material, length: MaterialProperties.stride, index: 1)
//        
//        model.draw(renderEncoder, submeshesToDisplay: submeshesToRender)
//    }
//    
//    func doRenderShadow(_ renderEncoder: MTLRenderCommandEncoder, submeshesToRender: [String: Bool]? = nil) {
//        // NOT IMPLEMENTED
//        fatalError("NOT IMPLEMENTED")
//    }
//}

// Material Properties
extension InstancedGameObject {
    public func setColor(_ color: SIMD4<Float>) {
        self._material?.color = color
    }
}
