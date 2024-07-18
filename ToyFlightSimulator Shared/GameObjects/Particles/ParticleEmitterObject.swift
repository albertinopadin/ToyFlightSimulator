//
//  ParticleEmitterObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/18/24.
//
import MetalKit

class ParticleEmitterObject: GameObject, ParticleEmitterEntity {
    let emitter: ParticleEmitter
    
    init(name: String,
         emitter: ParticleEmitter,
         meshType: MeshType = .None,
         renderPipelineStateType: RenderPipelineStateType = .Particle) {
        self.emitter = emitter
        super.init(name: name, meshType: meshType, renderPipelineStateType: renderPipelineStateType)
    }
    
    override func update() {
        super.update()
        emitter.emit()
    }
    
    func computeUpdate(_ computeEncoder: any MTLComputeCommandEncoder, threadsPerGroup: MTLSize) {
        if emitter.currentParticles > 0 {
            let threadsPerGrid = MTLSize(width: emitter.particleCount, height: 1, depth: 1)
            computeEncoder.setBuffer(emitter.particleBuffer, offset: 0, index: 0)
            computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        }
    }
    
    override func doRender(_ renderEncoder: any MTLRenderCommandEncoder,
                           applyMaterials: Bool = true,
                           submeshesToRender: [String : Bool]? = nil) {
        if emitter.currentParticles > 0 {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Particle])
            renderEncoder.setVertexBuffer(emitter.particleBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBytes(&emitter.position, length: float3.stride, index: 2)
            
            renderEncoder.setVertexBytes(&_modelConstants,
                                         length: ModelConstants.stride,
                                         index: TFSBufferModelConstants.index)
            
            if let emitterTexture = emitter.particleTexture {
                renderEncoder.setFragmentTexture(emitterTexture, index: TFSTextureIndexParticle.index)
            }
            
            renderEncoder.drawPrimitives(type: .point,
                                         vertexStart: 0,
                                         vertexCount: 1,
                                         instanceCount: emitter.currentParticles)
        }
    }
    
    override func setPosition(_ position: float3) {
        self.emitter.position = position
        super.setPosition(position)
    }
    
    override func setPosition(_ x: Float, _ y: Float, _ z: Float) {
        let newPosition: float3 = [x, y, z]
        self.setPosition(newPosition)
    }
    
    override func setPositionX(_ xPosition: Float) {
        self.emitter.position.x = xPosition
        super.setPositionX(xPosition)
    }
    
    override func setPositionY(_ yPosition: Float) {
        self.emitter.position.y = yPosition
        super.setPositionY(yPosition)
    }
    
    override func setPositionZ(_ zPosition: Float) {
        self.emitter.position.y = zPosition
        super.setPositionZ(zPosition)
    }
    
    override func move(_ deltaPosition: float3) {
        self.emitter.position += deltaPosition
        super.move(deltaPosition)
    }
    
    override func move(_ x: Float, _ y: Float, _ z: Float) {
        let deltaPosition: float3 = [x, y, z]
        self.move(deltaPosition)
    }
    
    override func moveX(_ delta: Float) {
        self.emitter.position.x += delta
        super.moveX(delta)
    }
    
    override func moveY(_ delta: Float) {
        self.emitter.position.y += delta
        super.moveY(delta)
    }
    
    override func moveZ(_ delta: Float) {
        self.emitter.position.z += delta
        super.moveZ(delta)
    }
    
    override func moveAlongVector(_ vector: float3, distance: Float) {
        // TODO
        super.moveAlongVector(vector, distance: distance)
    }
}

