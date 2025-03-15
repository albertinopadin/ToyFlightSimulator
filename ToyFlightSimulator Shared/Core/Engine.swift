//
//  Engine.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/25/22.
//

import MetalKit

class Engine {
    public static var Device: MTLDevice!
    public static var CommandQueue: MTLCommandQueue!
    public static var DefaultLibrary: MTLLibrary!
    
    public static var renderer: Renderer!
    
    private static var updateThread: Thread!
    private static let updateSemaphore = DispatchSemaphore(value: 0)
    private static var updatePreviousTime: UInt64 = 0
    
    public static func Start(device: MTLDevice, rendererType: RendererType) {
        self.Device = device
        self.CommandQueue = device.makeCommandQueue()
        self.DefaultLibrary = device.makeDefaultLibrary()
        
        Graphics.Initialize()
        Assets.Initialize()
        InputManager.Initialize()
        
        updateThread = makeUpdateThread()
        updateThread.start()
        
        self.renderer = InitRenderer(type: rendererType)
        self.renderer.updateSemaphore = updateSemaphore
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
    
    private static func makeUpdateThread() -> Thread {
        let ut = Thread {
            while true {
                _ = self.updateSemaphore.wait(timeout: .distantFuture)
                
                let currentTime = DispatchTime.now().uptimeNanoseconds
                let updateDeltaTime = Double(currentTime - self.updatePreviousTime) / 1e9
                self.updatePreviousTime = currentTime
                SceneManager.Update(deltaTime: updateDeltaTime)
                GameStatsManager.sharedInstance.sceneUpdated()
            }
        }
        ut.name = "UpdateThread"
        ut.qualityOfService = .userInteractive
        return ut
    }
}
