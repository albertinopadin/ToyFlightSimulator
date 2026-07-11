//
//  Engine.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/25/22.
//

@preconcurrency import MetalKit

final class Engine {
    public static let Device: MTLDevice = {
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("[Engine] Metal is not supported on this device.")
        }
        return defaultDevice
    }()
    
    public static let CommandQueue: MTLCommandQueue = {
        guard let commandQueue = Engine.Device.makeCommandQueue() else {
            fatalError("[Engine] Could not create command queue.")
        }
        return commandQueue
    }()
    
    public static let DefaultLibrary: MTLLibrary = {
        guard let defaultLibrary = Engine.Device.makeDefaultLibrary() else {
            fatalError("[Engine] Could not create default library.")
        }
        return defaultLibrary
    }()
    
    nonisolated(unsafe) public static var renderer: Renderer?
    
    nonisolated(unsafe) private static let updateThread = UpdateThread(name: "UpdateThread", qos: .userInteractive)
    nonisolated(unsafe) private static let audioThread = AudioThread(name: "AudioThread", qos: .userInteractive)
    
    public static func Start(rendererType: RendererType) {
        updateThread.start()
        audioThread.start()
        
        DrawManager.InitializeRingBuffers()
        
        Engine.renderer = Engine.InitRenderer(type: rendererType)
    }
    
    // Not clear this belongs in the Engine class...
    public static func SceneBuildFinished() {
        // Kick the audio thread after the scene has initialized (prevents crackling).
        // The thread itself decides whether to play music or just warm up the engine.
        audioThread.startAudio()
    }
    
    /// Every renderer constructed here comes back wired to the shared
    /// UpdateThread's semaphores. The runtime renderer-switch paths in the
    /// platform view wrappers (updateNSView / updateUIView) install this
    /// result directly as `Engine.renderer` — an unwired renderer silently
    /// skips the render↔update handshake (`updateSemaphore?.signal()` /
    /// `updateDoneSemaphore?.wait()` are nil no-ops) and freezes the
    /// simulation after a live switch.
    public static func InitRenderer(type: RendererType) -> Renderer {
        let renderer: Renderer
        switch type {
            case .OrderIndependentTransparency:
                // Does not work if gameView.depthStencilPixelFormat = .depth32Float_stencil8
                renderer = OITRenderer()
            case .SinglePassDeferredLighting:
                renderer = SinglePassDeferredLightingRenderer()
            case .TiledDeferred:
                renderer = TiledDeferredRenderer()
            case .TiledDeferredMSAA:
                renderer = TiledMultisampleRenderer()
            case .TiledMSAATessellated:
                renderer = TiledMSAATessellatedRenderer()
            case .ForwardPlusTileShading:
                renderer = ForwardPlusTileShadingRenderer()
        }
        renderer.updateSemaphore = updateThread.updateSemaphore
        renderer.updateDoneSemaphore = updateThread.updateDoneSemaphore
        return renderer
    }
    
    public static var MetalView: MTKView? {
        get {
            return Engine.renderer?.metalView
        }
        
        set {
            Engine.renderer?.metalView = newValue!
        }
    }
    
    public static func PauseView(_ shouldPause: Bool) {
        DispatchQueue.main.async {
            Engine.renderer?.metalView.isPaused = shouldPause
        }
    }
}
