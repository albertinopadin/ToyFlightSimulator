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
        
        Engine.renderer = Engine.InitRenderer(type: rendererType)
        Engine.renderer!.updateSemaphore = Engine.updateThread.updateSemaphore
    }
    
    // Not clear this belongs in the Engine class...
    public static func SceneBuildFinished() {
        // Starting audio only after scene has initialized to prevent crackling:
        audioThread.startAudio()
    }
    
    public static func InitRenderer(type: RendererType) -> Renderer {
        switch type {
            case .OrderIndependentTransparency:
                // Does not work if gameView.depthStencilPixelFormat = .depth32Float_stencil8
                return OITRenderer()
            case .SinglePassDeferredLighting:
                return SinglePassDeferredLightingRenderer()
            case .TiledDeferred:
                return TiledDeferredRenderer()
            case .TiledDeferredMSAA:
                return TiledMultisampleRenderer()
            case .ForwardPlusTileShading:
                return ForwardPlusTileShadingRenderer()
        }
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
