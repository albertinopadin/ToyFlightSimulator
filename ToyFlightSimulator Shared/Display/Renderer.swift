//
//  Renderer.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/25/22.
//

import Metal
import MetalKit

//let MaxOutstandingFrameCount = 3
//let MaxConstantsSize = 1_024 * 1_024 * 256
//let MinBufferAlignment = 256
//let MaxNodeCount = 1000

//final class Renderer: NSObject, MTKViewDelegate {
//    let device: MTLDevice
//    let commandQueue: MTLCommandQueue
//    let view: MTKView
//
//    let pointOfView = Node()
//    var lights = [Light]()
//
//    var nodes: [Node]
//
//    private var vertexDescriptor: MTLVertexDescriptor!
//    private var renderPipelineState: MTLRenderPipelineState!
//
//    private var constantBuffer: MTLBuffer!
//    private var currentConstantBufferOffset = 0
//    private var frameConstantsOffset: Int = 0
//    private var lightConstantsOffset: Int = 0
//    private var nodeConstantsOffsets = [Int]()
//
//    private var frameSemaphore = DispatchSemaphore(value: MaxOutstandingFrameCount)
//    private var frameIndex = 0
//    private var time: TimeInterval = 0
//
//    private let projectionFrameNear: Float = 0.01
//    private let projectionFrameFar: Float = 500
//
//    private let updateQueue = DispatchQueue(label: "toyfs.update.queue",
//                                            qos: .userInteractive)
//
//    private var constantsBufferSize: Int = 0
//
//    init(device: MTLDevice, view: MTKView, gameVertexDescriptor: GameVertexDescriptor, nodes: [Node] = [Node]()) {
//        view.device = device
//        self.device = device
//        self.view = view
//        self.nodes = nodes
//        self.commandQueue = device.makeCommandQueue()!
//
//        super.init()
//
//        view.device = device
//        view.delegate = self
//        view.colorPixelFormat = .bgra8Unorm_srgb
//        view.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
//
//        vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(gameVertexDescriptor.mdlVertexDescriptor)!
//
//        makeScene()
//        makeResources()
//        makePipeline()
//    }
//
//    public func setNodes(_ nodes: [Node]) {
//        self.nodes = nodes
//    }
//
//    public func appendNode(_ node: Node) {
//        self.nodes.append(node)
//    }
//
//    public func appendNodes(_ nodes: [Node]) {
//        self.nodes.append(contentsOf: nodes)
//    }
//
//    func makeScene() {
//        let ambientLight = Light()
//        ambientLight.type = .ambient
//        ambientLight.intensity = 0.7
//
//        let localLight = Light()
//        localLight.type = .omni
//        localLight.intensity = 15.0
//        localLight.worldTransform = float4x4(lookAt: SIMD3<Float>(0, 0, -1),
//                                             from: SIMD3<Float>(0, 5, 0),
//                                             up: SIMD3<Float>(0, 1, 0))
//
//        let sunLight = Light()
//        sunLight.type = .directional
//        sunLight.intensity = 0.3
//        sunLight.worldTransform = simd_float4x4(lookAt: SIMD3<Float>(0, 0, 0),
//                                                from: SIMD3<Float>(1, 1, 1),
//                                                up: SIMD3<Float>(0, 1, 0))
//
//        lights = [ambientLight, sunLight, localLight]
//    }
//
//    func makeResources() {
////        let instanceConstantsSize = nodes.count * MemoryLayout<InstanceConstants>.self.stride
//        // Need MaxNodeCount here otherwise if initial nodes.count is 0, the instanceConstantsSize will also be zero:
//        let instanceConstantsSize = MaxNodeCount * MemoryLayout<InstanceConstants>.self.stride
//        let frameConstantsSize = MemoryLayout<FrameConstants>.self.stride
//        let lightConstantsSize = lights.count * MemoryLayout<LightConstants>.self.stride
//        constantsBufferSize = instanceConstantsSize + frameConstantsSize + lightConstantsSize
//        constantsBufferSize *= (MaxOutstandingFrameCount + 1)
//        print("constantsBufferSize: \(constantsBufferSize)")
//        print("constantsBufferSize (in MB): \(constantsBufferSize / (1024 * 1024))")
//        constantBuffer = device.makeBuffer(length: constantsBufferSize, options: .storageModeShared)
////        constantBuffer = device.makeBuffer(length: constantBufferLength, options: .storageModeManaged)
////        print("constantsBufferSize (in MB): \(MaxConstantsSize / (1024 * 1024))")
////        constantBuffer = device.makeBuffer(length: MaxConstantsSize, options: .storageModeShared)
//        constantBuffer.label = "Dynamic Constants Buffer"
//    }
//
//    func makePipeline() {
//        guard let library = device.makeDefaultLibrary() else {
//            fatalError("Unable to create default Metal library")
//        }
//
//        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
//        renderPipelineDescriptor.vertexDescriptor = vertexDescriptor
//        renderPipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
//        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_main")
//        renderPipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
//
//        do {
//            renderPipelineState = try device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
//        } catch {
//            fatalError("Error while creating render pipeline state: \(error)")
//        }
//    }
//
//    func allocateConstantStorage(size: Int, alignment: Int) -> Int {
//        let effectiveAlignment = lcm(alignment, MinBufferAlignment)
//        var allocationOffset = align(currentConstantBufferOffset, upTo: effectiveAlignment)
//        if (allocationOffset + size >= constantsBufferSize) {
//            allocationOffset = 0
//        }
//        currentConstantBufferOffset = allocationOffset + size
//        return allocationOffset
//    }
//
//    func updateFrameConstants() {
//        let aspectRatio = Float(view.drawableSize.width / view.drawableSize.height)
//        let projectionMatrix = simd_float4x4(perspectiveProjectionFoVY: .pi / 3,
//                                             aspectRatio: aspectRatio,
//                                             near: projectionFrameNear,
//                                             far: projectionFrameFar)
//
//        let cameraMatrix = pointOfView.worldTransform
//        let viewMatrix = cameraMatrix.inverse
//        var viewDirectionMatrix = viewMatrix
//        viewDirectionMatrix.columns.3 = SIMD4<Float>(0, 0, 0, 1)
//
//        var constants = FrameConstants(projectionMatrix: projectionMatrix,
//                                       viewMatrix: viewMatrix,
//                                       inverseViewDirectionMatrix: viewDirectionMatrix.inverse.upperLeft3x3,
//                                       lightCount: UInt32(lights.count))
//
//        let layout = MemoryLayout<FrameConstants>.self
//        frameConstantsOffset = allocateConstantStorage(size: layout.size, alignment: layout.stride)
//        let constantsPointer = constantBuffer.contents().advanced(by: frameConstantsOffset)
//        constantsPointer.copyMemory(from: &constants, byteCount: layout.size)
//    }
//
//    func updateLightConstants() {
//        let layout = MemoryLayout<LightConstants>.self
//        lightConstantsOffset = allocateConstantStorage(size: layout.stride * lights.count, alignment: layout.stride)
//        let lightsBufferPointer = constantBuffer.contents()
//            .advanced(by: lightConstantsOffset)
//            .assumingMemoryBound(to: LightConstants.self)
//
//        for (lightIndex, light) in lights.enumerated() {
//            let shadowViewMatrix = light.worldTransform.inverse
//            let shadowProjectionMatrix = light.projectionMatrix
//            let shadowViewProjectionMatrix = shadowProjectionMatrix * shadowViewMatrix
//            lightsBufferPointer[lightIndex] = LightConstants(viewProjectionMatrix: shadowViewProjectionMatrix,
//                                                             intensity: light.color * light.intensity,
//                                                             position: light.position,
//                                                             direction: light.direction,
//                                                             type: light.type.rawValue)
//        }
//    }
//
//    func updateNodeConstants(timestep: Float) {
//        nodeConstantsOffsets.removeAll()
//
//        let layout = MemoryLayout<InstanceConstants>.self
//        let offset = allocateConstantStorage(size: layout.stride * nodes.count, alignment: layout.stride)
//        let instanceConstants = constantBuffer.contents().advanced(by: offset).bindMemory(to: InstanceConstants.self,
//                                                                                          capacity: nodes.count)
//
//        let t_writeBuffer = timeit {
//            updateQueue.sync {
//                nodes.withUnsafeBufferPointer { buffer in
//                    DispatchQueue.concurrentPerform(iterations: self.nodes.count) { i in
//                        instanceConstants[i] = InstanceConstants(modelMatrix: buffer[i].transform,
//                                                                 color: buffer[i].color)
//                    }
//                }
//            }
//        }
//
//        nodeConstantsOffsets.append(offset)
//
//        print("[updateNodeConstants] Writing instance constants time: \(Double(t_writeBuffer)/1_000_000) ms")
//    }
//
//    func renderPassDescriptor(colorTexture: MTLTexture) -> MTLRenderPassDescriptor {
//        let renderPassDescriptor = MTLRenderPassDescriptor()
//        renderPassDescriptor.colorAttachments[0].texture = colorTexture
//        renderPassDescriptor.colorAttachments[0].loadAction = .clear
//        renderPassDescriptor.colorAttachments[0].clearColor = view.clearColor
//        renderPassDescriptor.colorAttachments[0].storeAction = .store
//        return renderPassDescriptor
//    }
//
//    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
//        // TODO if implement MSAA
//    }
//
//    func draw(in view: MTKView) {
//        let t_totalDraw = timeit {
//            // This blocks if 3 frames are already underway:
//            frameSemaphore.wait()
//
//            let initialConstantOffset = currentConstantBufferOffset
//            let timestep = 1.0 / Double(view.preferredFramesPerSecond)
//            time += timestep
//
//            let t_constants = timeit {
//                updateLightConstants()
//                updateFrameConstants()
//                let t_nodeConstants = timeit {
//                    updateNodeConstants(timestep: Float(timestep))
//                }
//                print("Run time for updating Node constants: \(Double(t_nodeConstants)/1_000_000) ms")
//            }
//            print("Run time for updating constants: \(Double(t_constants)/1_000_000) ms")
//
//            guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
//
//            guard let drawable = view.currentDrawable else { return }
//            let renderPassDescriptor = renderPassDescriptor(colorTexture: drawable.texture)
//
//            let t_main = timeit {
//                // Main pass:
//                // TODO: Can I pull this (makeRenderCommandEncoder) out of the draw loop?
//                let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
//                renderCommandEncoder.setFrontFacing(.counterClockwise)
//                renderCommandEncoder.setCullMode(.back)
//                renderCommandEncoder.setRenderPipelineState(renderPipelineState)
//
//                // Bind constants:
//                renderCommandEncoder.setVertexBuffer(constantBuffer, offset: frameConstantsOffset, index: 3)
//                renderCommandEncoder.setFragmentBuffer(constantBuffer, offset: frameConstantsOffset, index: 3)
//                renderCommandEncoder.setFragmentBuffer(constantBuffer, offset: lightConstantsOffset, index: 4)
//
//                let t_main_loop = timeit {
//                    for (nodeIndex, node) in nodes.enumerated() {
//                        if let mesh = node.mesh {
//                            renderCommandEncoder.setVertexBuffer(constantBuffer,
//                                                                 offset: nodeConstantsOffsets[nodeIndex],
//                                                                 index: 2)
//
//                            for (i, meshBuffer) in mesh.vertexBuffers.enumerated() {
//                                renderCommandEncoder.setVertexBuffer(meshBuffer.buffer, offset: meshBuffer.offset, index: i)
//                            }
//
//                            for submesh in mesh.submeshes {
//                                let indexBuffer = submesh.indexBuffer
//                                renderCommandEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
//                                                                           indexCount: submesh.indexCount,
//                                                                           indexType: submesh.indexType,
//                                                                           indexBuffer: indexBuffer.buffer,
//                                                                           indexBufferOffset: indexBuffer.offset)
//                            }
//                        }
//                    }
//                }
//
//                print("Run time for main draw pass loop: \(Double(t_main_loop)/1_000_000) ms")
//
//                renderCommandEncoder.endEncoding()
//                // END main pass
//            }
//            print("Run time for main draw pass: \(Double(t_main)/1_000_000) ms")
//
//            commandBuffer.present(drawable)
//            commandBuffer.addCompletedHandler { [weak self] _ in
//                self?.frameSemaphore.signal()
//            }
//            commandBuffer.commit()
//
//            let constantSize = currentConstantBufferOffset - initialConstantOffset
//            if (constantSize > constantsBufferSize / MaxOutstandingFrameCount) {
////                print("Insufficient constant storage: frame consumed \(constantSize) " +
////                      "bytes of total \(constantsBufferSize) bytes")
//            }
//
//            frameIndex += 1
//        }
//        print("Total Draw call Run Time: \(Double(t_totalDraw)/1_000_000) ms")
//    }
//}

class Renderer: NSObject, MTKViewDelegate {
    public static var ScreenSize = float2(0, 0)
    public static var AspectRatio: Float { return ScreenSize.x / ScreenSize.y }
    
    private var _baseRenderPassDescriptor: MTLRenderPassDescriptor!
    private var _forwardRenderPassDescriptor: MTLRenderPassDescriptor!
    private let _optimalTileSize: MTLSize = MTLSize(width: 32, height: 16, depth: 1)
    
    init(_ mtkView: MTKView) {
        super.init()
        updateScreenSize(view: mtkView)
        createBaseRenderPassDescriptor()
        createForwardRenderPassDescriptor()
        mtkView.delegate = self
    }
    
    private func createBaseRenderPassDescriptor() {
        // --- BASE COLOR 0 TEXTURE ---
        let base0TextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.MainPixelFormat,
                                                                              width: Int(Renderer.ScreenSize.x),
                                                                              height: Int(Renderer.ScreenSize.y),
                                                                              mipmapped: false)
        // Defining render target
        base0TextureDescriptor.usage = [.renderTarget, .shaderRead]
        Assets.Textures.setTexture(textureType: .BaseColorRender_0,
                                   texture: Engine.Device.makeTexture(descriptor: base0TextureDescriptor)!)
        
        // --- BASE COLOR 1 TEXTURE ---
        let base1TextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.MainPixelFormat,
                                                                              width: Int(Renderer.ScreenSize.x),
                                                                              height: Int(Renderer.ScreenSize.y),
                                                                              mipmapped: false)
        // Defining render target
        base1TextureDescriptor.usage = [.renderTarget, .shaderRead]
        Assets.Textures.setTexture(textureType: .BaseColorRender_1,
                                   texture: Engine.Device.makeTexture(descriptor: base1TextureDescriptor)!)
        
        // --- BASE DEPTH TEXTURE ---
        let depthTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.MainDepthPixelFormat,
                                                                              width: Int(Renderer.ScreenSize.x),
                                                                              height: Int(Renderer.ScreenSize.y),
                                                                              mipmapped: false)
        // Defining render target
        depthTextureDescriptor.usage = [.renderTarget, .shaderRead]
        depthTextureDescriptor.storageMode = .private
        Assets.Textures.setTexture(textureType: .BaseDepthRender,
                                   texture: Engine.Device.makeTexture(descriptor: depthTextureDescriptor)!)
        
        _baseRenderPassDescriptor = MTLRenderPassDescriptor()
        _baseRenderPassDescriptor.colorAttachments[0].texture = Assets.Textures[.BaseColorRender_0]
        _baseRenderPassDescriptor.colorAttachments[0].storeAction = .store
        _baseRenderPassDescriptor.colorAttachments[0].loadAction = .clear
        
        _baseRenderPassDescriptor.colorAttachments[1].texture = Assets.Textures[.BaseColorRender_1]
        _baseRenderPassDescriptor.colorAttachments[1].storeAction = .store
        _baseRenderPassDescriptor.colorAttachments[1].loadAction = .clear
        
        _baseRenderPassDescriptor.depthAttachment.texture = Assets.Textures[.BaseDepthRender]
        _baseRenderPassDescriptor.depthAttachment.storeAction = .store
        _baseRenderPassDescriptor.depthAttachment.loadAction = .clear
        
        // For Order-Independent Blending:
        _baseRenderPassDescriptor.tileWidth = _optimalTileSize.width
        _baseRenderPassDescriptor.tileHeight = _optimalTileSize.height
        _baseRenderPassDescriptor.imageblockSampleLength = Graphics.RenderPipelineStates[.OrderIndependentTransparent].imageblockSampleLength
    }
    
    private func createForwardRenderPassDescriptor() {
        // --- BASE COLOR 0 TEXTURE ---
        let base0TextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.MainPixelFormat,
                                                                              width: Int(Renderer.ScreenSize.x),
                                                                              height: Int(Renderer.ScreenSize.y),
                                                                              mipmapped: false)
        // Defining render target
        base0TextureDescriptor.usage = [.renderTarget, .shaderRead]
        Assets.Textures.setTexture(textureType: .BaseColorRender_0,
                                   texture: Engine.Device.makeTexture(descriptor: base0TextureDescriptor)!)
        
        // --- BASE DEPTH TEXTURE ---
        let depthTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.MainDepthPixelFormat,
                                                                              width: Int(Renderer.ScreenSize.x),
                                                                              height: Int(Renderer.ScreenSize.y),
                                                                              mipmapped: false)
        // Defining render target
        depthTextureDescriptor.usage = [.renderTarget, .shaderRead]
        depthTextureDescriptor.storageMode = .private
        Assets.Textures.setTexture(textureType: .BaseDepthRender,
                                   texture: Engine.Device.makeTexture(descriptor: depthTextureDescriptor)!)
        
        _forwardRenderPassDescriptor = MTLRenderPassDescriptor()
        _forwardRenderPassDescriptor.colorAttachments[0].texture = Assets.Textures[.BaseColorRender_0]
        _forwardRenderPassDescriptor.colorAttachments[0].storeAction = .store
        _forwardRenderPassDescriptor.colorAttachments[0].loadAction = .clear
        
        _forwardRenderPassDescriptor.depthAttachment.texture = Assets.Textures[.BaseDepthRender]
        _forwardRenderPassDescriptor.depthAttachment.storeAction = .store
        _forwardRenderPassDescriptor.depthAttachment.loadAction = .clear
        
        // For Order-Independent Blending:
        _forwardRenderPassDescriptor.tileWidth = _optimalTileSize.width
        _forwardRenderPassDescriptor.tileHeight = _optimalTileSize.height
        _forwardRenderPassDescriptor.imageblockSampleLength = Graphics.RenderPipelineStates[.OrderIndependentTransparent].imageblockSampleLength
    }
    
    
    // --- MTKViewDelegate methods ---
    public func updateScreenSize(view: MTKView) {
        Renderer.ScreenSize = float2(Float(view.drawableSize.width), Float(view.drawableSize.height))
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // When window is resized
        updateScreenSize(view: view)
    }
    
    func drawOpaqueObjects(renderCommandEncoder: MTLRenderCommandEncoder) {
        renderCommandEncoder.pushDebugGroup("Opaque Object Rendering")
        renderCommandEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Opaque])
        renderCommandEncoder.setCullMode(.none)
        renderCommandEncoder.setDepthStencilState(Graphics.DepthStencilStates[.LessEqualWrite])
        
        // TODO: Draw opaque objects... somehow!
        SceneManager.RenderOpaque(renderCommandEncoder: renderCommandEncoder)
        
        renderCommandEncoder.popDebugGroup()
    }
    
    func drawTransparentObjects(renderCommandEncoder: MTLRenderCommandEncoder) {
        renderCommandEncoder.pushDebugGroup("Transparent Object Rendering")
        renderCommandEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.OrderIndependentTransparent])
        renderCommandEncoder.setCullMode(.none)
        renderCommandEncoder.setDepthStencilState(Graphics.DepthStencilStates[.LessEqualNoWrite])
        
        // TODO: Draw transparent objects... somehow!
        SceneManager.RenderTransparent(renderCommandEncoder: renderCommandEncoder)
        
        renderCommandEncoder.popDebugGroup()
    }
    
    func baseRenderPass(commandBuffer: MTLCommandBuffer) {
        let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: _baseRenderPassDescriptor)
        renderCommandEncoder?.label = "Base Render Command Encoder"
        renderCommandEncoder?.pushDebugGroup("Starting Base Render")
        SceneManager.Render(renderCommandEncoder: renderCommandEncoder!)
        renderCommandEncoder?.popDebugGroup()
        renderCommandEncoder?.endEncoding()
    }
    
    func orderIndependentTransparencyRenderPass(view: MTKView, commandBuffer: MTLCommandBuffer) {
        guard let drawableTexture = view.currentDrawable?.texture else { return }
        
        _baseRenderPassDescriptor.colorAttachments[0].texture = drawableTexture
        _baseRenderPassDescriptor.depthAttachment.texture = view.depthStencilTexture
        
        let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: _forwardRenderPassDescriptor)
        renderCommandEncoder?.label = "Order Independent Transparency Render Command Encoder"
        
        renderCommandEncoder?.pushDebugGroup("[Tile Render] Init Image Block")
        renderCommandEncoder?.setRenderPipelineState(Graphics.RenderPipelineStates[.TileRender])
        renderCommandEncoder?.dispatchThreadsPerTile(_optimalTileSize)
        renderCommandEncoder?.popDebugGroup()
        
        drawOpaqueObjects(renderCommandEncoder: renderCommandEncoder!)
        drawTransparentObjects(renderCommandEncoder: renderCommandEncoder!)
        
        renderCommandEncoder?.pushDebugGroup("Blend Fragments")
        renderCommandEncoder?.setRenderPipelineState(Graphics.RenderPipelineStates[.Blend])
        renderCommandEncoder?.setCullMode(.none)
        renderCommandEncoder?.setDepthStencilState(Graphics.DepthStencilStates[.AlwaysNoWrite])
        renderCommandEncoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        renderCommandEncoder?.popDebugGroup()
        
        renderCommandEncoder?.endEncoding()
    }
    
    func finalRenderPass(view: MTKView, commandBuffer: MTLCommandBuffer) {
        let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: view.currentRenderPassDescriptor!)
        renderCommandEncoder?.label = "Final Render Command Encoder"
        renderCommandEncoder?.pushDebugGroup("Starting Final Render")
        
        renderCommandEncoder?.setRenderPipelineState(Graphics.RenderPipelineStates[.Final])
        renderCommandEncoder?.setFragmentTexture(Assets.Textures[.BaseColorRender_0], index: 0)
        Assets.Meshes[.Quad].drawPrimitives(renderCommandEncoder!)
        
        renderCommandEncoder?.popDebugGroup()
        renderCommandEncoder?.endEncoding()
    }
    
    func draw(in view: MTKView) {
        SceneManager.Update(deltaTime: 1.0 / Float(view.preferredFramesPerSecond))
        
        let commandBuffer = Engine.CommandQueue.makeCommandBuffer()
        commandBuffer?.label = "Base Command Buffer"
        
//        baseRenderPass(commandBuffer: commandBuffer!)
        orderIndependentTransparencyRenderPass(view: view, commandBuffer: commandBuffer!)
        // Intermediate renders go here
        finalRenderPass(view: view, commandBuffer: commandBuffer!)
        
        commandBuffer?.present(view.currentDrawable!)
        commandBuffer?.commit()
    }
}
