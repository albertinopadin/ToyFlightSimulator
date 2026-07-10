//
//  IOSMetalViewWrapper.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 8/5/23.
//

import SwiftUI

struct IOSMetalViewWrapper: UIViewRepresentable {
    typealias UIViewType = GameView
    
    var viewSize: CGSize
    var refreshRate: FPS
    // TODO: SinglePassDeferredLighting doesn't work on iOS due to a memory issue.
    var rendererType: RendererType
    
    func makeCoordinator() -> Void {
        Engine.Start(rendererType: rendererType)
    }
    
    func makeUIView(context: Context) -> GameView {
        let gameView = GameView()
        gameView.device = Engine.Device
        gameView.clearColor = Preferences.ClearColor
        gameView.colorPixelFormat = Preferences.MainPixelFormat
        gameView.framebufferOnly = true
        gameView.preferredFramesPerSecond = refreshRate.rawValue
        gameView.drawableSize = viewSize
        
        Engine.MetalView = gameView
        SceneManager.SetScene(Preferences.StartingSceneType,
                              rendererType: Engine.renderer!.rendererType)

        // The Metal Performance HUD subsystem is armed by the MTL_HUD_ENABLED=1
        // scheme env var (Debug). Start it hidden so the toggle button reveals it.
        MetalPerformanceHUD.setEnabled(false)

        return gameView
    }
    
    func updateUIView(_ nsView: UIViewType, context: Context) {
        // Runtime renderer switching, mirroring MacMetalViewWrapper.updateNSView.
        if rendererType != Engine.renderer!.rendererType {
            SceneManager.TeardownScene()
            let newRenderer = Engine.InitRenderer(type: rendererType)
            newRenderer.metalView = nsView
            Engine.renderer = newRenderer
            SceneManager.SetScene(Preferences.StartingSceneType,
                                  rendererType: rendererType)
            SceneManager.Paused = true
        }

        Engine.MetalView!.preferredFramesPerSecond = refreshRate.rawValue
        
        // Query renderer to see if screen size has already been set: (is there a better way to do this...?)
        if !((Engine.renderer as? OITRenderer)?.alreadySetScreenSize ?? false) {
            let newSize = nsView.bounds.size
            print("[updateUIView] newSize: \(newSize)")
            if newSize.width > 0 && newSize.width.isNormal && newSize.height > 0 && newSize.height.isNormal {
                Engine.MetalView!.drawableSize = nsView.bounds.size
            }
        }
    }
}

struct IOSMetalViewWrapper_Previews: PreviewProvider {
    static var previewSize = CGSize(width: 1920, height: 1080)
    static var previews: some View {
        IOSMetalViewWrapper(viewSize: previewSize, refreshRate: .FPS_120, rendererType: .TiledMSAATessellated)
    }
}

