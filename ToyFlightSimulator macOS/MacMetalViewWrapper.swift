//
//  MacMetalViewWrapper.swift
//  ToyFlightSimulator macOS
//
//  Created by Albertino Padin on 7/30/23.
//

import SwiftUI

class TFSCoordinator {
    var renderer: Renderer
    
    init(renderer: Renderer) {
        self.renderer = renderer
    }
}

struct MacMetalViewWrapper: NSViewRepresentable {
    typealias NSViewType = GameView
    
    var viewSize: CGSize
    var refreshRate: FPS
    var rendererType: RendererType
    
    func makeCoordinator() -> TFSCoordinator {
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        
        Engine.Start(device: defaultDevice)
        let renderer = initRenderer(type: rendererType)
        return TFSCoordinator(renderer: renderer)
    }
    
    func initRenderer(type: RendererType) -> Renderer {
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
    
    func makeNSView(context: Context) -> GameView {
        let gameView = GameView()
        gameView.device = Engine.Device
        gameView.clearColor = Preferences.ClearColor
        gameView.colorPixelFormat = Preferences.MainPixelFormat
        gameView.framebufferOnly = false
        gameView.preferredFramesPerSecond = refreshRate.rawValue
        gameView.drawableSize = viewSize
        
        context.coordinator.renderer.metalView = gameView
        SceneManager.SetScene(Preferences.StartingSceneType,
                              mtkView: gameView,
                              rendererType: context.coordinator.renderer.rendererType)
        
        return gameView
    }
    
    func updateNSView(_ nsView: NSViewType, context: Context) {
        print("[updateNSView] renderer type: \(rendererType)")
        if rendererType != context.coordinator.renderer.rendererType {
//            nsView.isPaused = true
            SceneManager.TeardownScene()
            let newRenderer = initRenderer(type: rendererType)
            newRenderer.metalView = nsView
            context.coordinator.renderer = newRenderer
            SceneManager.SetScene(Preferences.StartingSceneType,
                                  mtkView: nsView,
                                  rendererType: context.coordinator.renderer.rendererType)
            SceneManager.Paused = true
        }
        
        let newSize = nsView.bounds.size
        if newSize.width > 0 && newSize.width.isNormal && newSize.height > 0 && newSize.height.isNormal {
            context.coordinator.renderer.metalView.drawableSize = nsView.bounds.size
            context.coordinator.renderer.metalView.preferredFramesPerSecond = refreshRate.rawValue
        }
    }
}

struct MacMetalViewWrapper_Previews: PreviewProvider {
    static var previewSize = CGSize(width: 1920, height: 1080)
    static var previews: some View {
        MacMetalViewWrapper(viewSize: previewSize, refreshRate: .FPS_120, rendererType: .TiledDeferred)
    }
}
