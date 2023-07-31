//
//  MetalViewWrapper.swift
//  ToyFlightSimulator macOS
//
//  Created by Albertino Padin on 7/30/23.
//

import SwiftUI

struct MetalViewWrapper: NSViewRepresentable {
    var viewSize: CGSize
    
    func makeCoordinator() -> Renderer {
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        
        Engine.Start(device: defaultDevice)
//        let rendererType: RendererType = .OrderIndependentTransparency
        let rendererType: RendererType = .SinglePassDeferredLighting
        let renderer = initRenderer(type: rendererType)
        return renderer
    }
    
    func initRenderer(type: RendererType) -> Renderer {
        switch type {
            case .OrderIndependentTransparency:
                // Does not work if gameView.depthStencilPixelFormat = .depth32Float_stencil8
                return OITRenderer()
            case .SinglePassDeferredLighting:
                return SinglePassDeferredLightingRenderer()
        }
    }
    
    func makeNSView(context: Context) -> GameView {
        let gameView = GameView()
        gameView.device = Engine.Device
        gameView.clearColor = Preferences.ClearColor
        gameView.colorPixelFormat = Preferences.MainPixelFormat
        gameView.framebufferOnly = false
        gameView.preferredFramesPerSecond = 120
        gameView.drawableSize = viewSize
        print("[makeNSView] gameView bounds: \(gameView.bounds)")
        print("[MetalViewWrapper makeNSView] viewSize: \(viewSize)")
        print("[MetalViewWrapper makeNSView] gameView drawableSize: \(gameView.drawableSize)")
        
        context.coordinator.metalView = gameView
        SceneManager.SetScene(Preferences.StartingSceneType, rendererType: context.coordinator.rendererType)
        
        return gameView
    }
    
    func updateNSView(_ nsView: NSViewType, context: Context) {
        print("[MetalViewWrapper updateNSView]")
        print("[MetalViewWrapper updateNSView] drawableSize: \(nsView.drawableSize)")
        print("[MetalViewWrapper updateNSView] nsView.bounds.size: \(nsView.bounds.size)")
        print("[MetalViewWrapper updateNSView] nsView.frame.size: \(nsView.frame.size)")
//        print("[MetalViewWrapper updateNSView] nsView.frame.size: \(nsView.)")
        // TODO ?
        context.coordinator.metalView.drawableSize = nsView.bounds.size
    }
}

struct MetalViewWrapper_Previews: PreviewProvider {
    static var previewSize = CGSize(width: 1920, height: 1080)
    static var previews: some View {
        MetalViewWrapper(viewSize: previewSize)
    }
}
