//
//  MacMetalViewWrapper.swift
//  ToyFlightSimulator macOS
//
//  Created by Albertino Padin on 7/30/23.
//

import SwiftUI

struct MacMetalViewWrapper: NSViewRepresentable {
    typealias NSViewType = GameView
    
    var viewSize: CGSize
    var refreshRate: FPS
    var rendererType: RendererType
    
    func makeCoordinator() -> Void {
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        
        Engine.Start(device: defaultDevice, rendererType: rendererType)
    }
    
    
    
    func makeNSView(context: Context) -> GameView {
        let gameView = GameView()
        gameView.device = Engine.Device
        gameView.clearColor = Preferences.ClearColor
        gameView.colorPixelFormat = Preferences.MainPixelFormat
        gameView.framebufferOnly = false
        gameView.preferredFramesPerSecond = refreshRate.rawValue
        gameView.drawableSize = viewSize
        
        Engine.renderer.metalView = gameView
        SceneManager.SetScene(Preferences.StartingSceneType,
                              mtkView: gameView,
                              rendererType: Engine.renderer.rendererType)
        
        return gameView
    }
    
    func updateNSView(_ nsView: NSViewType, context: Context) {
        print("[updateNSView] renderer type: \(rendererType)")
        if rendererType != Engine.renderer.rendererType {
//            nsView.isPaused = true
            SceneManager.TeardownScene()
            let newRenderer = Engine.InitRenderer(type: rendererType)
            newRenderer.metalView = nsView
            Engine.renderer = newRenderer
            SceneManager.SetScene(Preferences.StartingSceneType,
                                  mtkView: nsView,
                                  rendererType: Engine.renderer.rendererType)
            SceneManager.Paused = true
        }
        
        let newSize = nsView.bounds.size
        if newSize.width > 0 && newSize.width.isNormal && newSize.height > 0 && newSize.height.isNormal {
            Engine.renderer.metalView.drawableSize = nsView.bounds.size
            Engine.renderer.metalView.preferredFramesPerSecond = refreshRate.rawValue
        }
    }
}

struct MacMetalViewWrapper_Previews: PreviewProvider {
    static var previewSize = CGSize(width: 1920, height: 1080)
    static var previews: some View {
        MacMetalViewWrapper(viewSize: previewSize, refreshRate: .FPS_120, rendererType: .TiledDeferred)
    }
}
