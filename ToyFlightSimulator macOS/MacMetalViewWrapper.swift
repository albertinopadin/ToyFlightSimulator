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
        Engine.Start(rendererType: rendererType)
    }
    
    
    
    func makeNSView(context: Context) -> GameView {
        guard let rendererType = Engine.renderer?.rendererType else {
            fatalError("[MacMetalViewWrapper makeNSView] Engine does not have a specified renderer.")
        }
        
        let gameView = GameView()
        gameView.device = Engine.Device
        gameView.clearColor = Preferences.ClearColor
        gameView.colorPixelFormat = Preferences.MainPixelFormat
        gameView.framebufferOnly = false
        gameView.preferredFramesPerSecond = refreshRate.rawValue
        gameView.drawableSize = viewSize
        
        Engine.MetalView = gameView
        SceneManager.SetScene(Preferences.StartingSceneType,
                              rendererType: rendererType)
        
        return gameView
    }
    
    func updateNSView(_ nsView: NSViewType, context: Context) {
        print("[updateNSView] renderer type: \(rendererType)")
        if rendererType != Engine.renderer!.rendererType {
//            nsView.isPaused = true
            SceneManager.TeardownScene()
            let newRenderer = Engine.InitRenderer(type: rendererType)
            newRenderer.metalView = nsView
            Engine.renderer = newRenderer
            SceneManager.SetScene(Preferences.StartingSceneType,
                                  rendererType: rendererType)
            SceneManager.Paused = true
        }
        
        let newSize = nsView.bounds.size
        if newSize.width > 0 && newSize.width.isNormal && newSize.height > 0 && newSize.height.isNormal {
            Engine.MetalView!.drawableSize = nsView.bounds.size
            Engine.MetalView!.preferredFramesPerSecond = refreshRate.rawValue
        }
    }
}

struct MacMetalViewWrapper_Previews: PreviewProvider {
    static var previewSize = CGSize(width: 1920, height: 1080)
    static var previews: some View {
        MacMetalViewWrapper(viewSize: previewSize, refreshRate: .FPS_120, rendererType: .TiledDeferred)
    }
}
