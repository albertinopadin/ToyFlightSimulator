//
//  Renderer.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/25/22.
//

import MetalKit

class Renderer: NSObject, MTKViewDelegate, BaseRenderer {
    nonisolated(unsafe) public static var ScreenSize = float2(100, 100)
    public static var AspectRatio: Float { return ScreenSize.x / ScreenSize.y }
    
    private var renderPreviousTime: UInt64 = 0
    private var renderDeltaTime: Double = 0
    
    // The max number of command buffers in flight
    let maxFramesInFlight = 3
    // The semaphore used to control GPU-CPU synchronization of frames.
    private let inFlightSemaphore: DispatchSemaphore
    
    // Used to control scene update frequency
    public var updateSemaphore: DispatchSemaphore?
    
    var baseRenderPassDescriptor: MTLRenderPassDescriptor
    
    public let rendererType: RendererType
    
    private var _metalView: MTKView!
    public var metalView: MTKView {
        get {
            return _metalView
        }
        
        set {
            _metalView = newValue
            
            MainActor.assumeIsolated {
                updateScreenSize(size: _metalView.drawableSize)
                Self.updateBaseRenderPassDescriptor(&baseRenderPassDescriptor,
                                                    screenWidth: Int(Renderer.ScreenSize.x),
                                                    screenHeight: Int(Renderer.ScreenSize.y))
                _metalView.delegate = self
            }
        }
    }
    
    init(type: RendererType) {
        self.rendererType = type
        inFlightSemaphore = DispatchSemaphore(value: maxFramesInFlight)
        baseRenderPassDescriptor = Self.createBaseRenderPassDescriptor(screenWidth: Int(Renderer.ScreenSize.x),
                                                                       screenHeight: Int(Renderer.ScreenSize.y))
        super.init()
    }
    
    init(_ mtkView: MTKView, type: RendererType) {
        self.rendererType = type
        inFlightSemaphore = DispatchSemaphore(value: maxFramesInFlight)
        baseRenderPassDescriptor = Self.createBaseRenderPassDescriptor(screenWidth: Int(Renderer.ScreenSize.x),
                                                                       screenHeight: Int(Renderer.ScreenSize.y))
        super.init()
        metalView = mtkView
    }
    
    // Heavily inspired by:
    // https://developer.apple.com/documentation/metal/metal_sample_code_library/rendering_a_scene_with_deferred_lighting_in_swift
    
    func runDrawableCommands(_ commandBlock: (MTLCommandBuffer) -> ()) {
        // Wait to ensure only maxFramesInFlight are getting processed by any stage in the Metal
        // pipeline (App, Metal, Drivers, GPU, etc)
        //inFlightSemaphore.wait()
        _ = inFlightSemaphore.wait(timeout: .distantFuture)
        
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else {
            fatalError("Failed to make command buffer from command queue")
        }
        
        commandBlock(commandBuffer)
        
        // Add completion hander which signals inFlightSemaphore
        // when Metal and the GPU has fully finished processing the commands encoded for this frame.
        // This indicates when the dynamic buffers, written this frame, will no longer be needed by Metal and the GPU.
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.inFlightSemaphore.signal()
        }
        
        commandBuffer.commit()
    }
    
    func encodeComputePass(into commandBuffer: MTLCommandBuffer,
                           label: String,
                           _ encodingBlock: (MTLComputeCommandEncoder) -> Void) {
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            fatalError("Failed to make compute command encoder.")
        }
        
        computeEncoder.label = label
        encodingBlock(computeEncoder)
        computeEncoder.endEncoding()
    }
    
    func encodeRenderPass(into commandBuffer: MTLCommandBuffer,
                          using descriptor: MTLRenderPassDescriptor,
                          label: String,
                          _ encodingBlock: (MTLRenderCommandEncoder) -> Void) {
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            fatalError("Failed to make render command encoder with: \(descriptor.description)")
        }
        
        renderEncoder.label = label
        encodingBlock(renderEncoder)
        renderEncoder.endEncoding()
    }
    
    func encodeRenderStage(using renderEncoder: MTLRenderCommandEncoder, label: String, _ encodingBlock: () -> Void) {
        renderEncoder.pushDebugGroup(label)
        encodingBlock()
        renderEncoder.popDebugGroup()
    }
    
    // --- MTKViewDelegate methods ---
    public func updateScreenSize(size: CGSize) {
        print("[Renderer updateScreenSize] new size: \(size)")
        if size.width > 0 && size.width.isFinite && size.height > 0 && size.height.isFinite {
            Renderer.ScreenSize = float2(Float(size.width), Float(size.height))
            print("[Renderer updateScreenSize] aspect ratio: \(Renderer.AspectRatio)")
            SceneManager.SetAspectRatio(Renderer.AspectRatio)
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        print("[Renderer drawableSizeWillChange]")
        // When window is resized
        if !size.width.isNaN && !size.height.isNaN {
            updateScreenSize(size: size)
            Self.updateBaseRenderPassDescriptor(&baseRenderPassDescriptor,
                                                screenWidth: Int(Renderer.ScreenSize.x),
                                                screenHeight: Int(Renderer.ScreenSize.y))
        }
    }
    
    func draw(in view: MTKView) {
        // Override & call render()
    }
    
    public func render(_ renderBlock: () -> ()) {
        updateSemaphore?.signal()
        
        let currentTime = DispatchTime.now().uptimeNanoseconds
        self.renderDeltaTime = Double(currentTime - self.renderPreviousTime) / 1e9
        self.renderPreviousTime = currentTime
        GameStatsManager.sharedInstance.recordRenderDeltaTime(self.renderDeltaTime)
        
        renderBlock()
        
        GameStatsManager.sharedInstance.frameRendered()
        
        updateSemaphore?.signal()
    }
}
