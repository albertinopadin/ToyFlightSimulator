//
//  MacGameUIView.swift
//  ToyFlightSimulator macOS
//
//  Created by Albertino Padin on 7/30/23.
//

import SwiftUI

struct MacGameUIView: View {
    private let minViewSize = CGSize(width: 640, height: 480)
    
    @State private var viewSize: CGSize = .zero
    @State private var shouldDisplayMenu: Bool = false
    @State private var shouldDisplayGameStats: Bool = false
    @State private var framesPerSecond: FPS = .FPS_120
    @State private var rendererType: RendererType = .TiledDeferredMSAA
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MacMetalViewWrapper(viewSize: getViewSize(geometrySize: viewSize),
                                    refreshRate: framesPerSecond,
                                    rendererType: rendererType)
                
                if shouldDisplayMenu {
                    TFSMenu(framesPerSecond: $framesPerSecond, rendererType: $rendererType, viewSize: viewSize)
                }
                
                if shouldDisplayGameStats {
                    GameStats(viewSize: viewSize)
                }
            }
            .onAppear {
                viewSize = getViewSize(geometrySize: geometry.size)
            }
            .onChange(of: geometry.size) { oldSize, newSize in
                viewSize = newSize
            }
        }
        .frame(minWidth: minViewSize.width, minHeight: minViewSize.height)
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { _ in
                InputManager.HandleKeyPressedDebounced(keyCode: .escape) {
                    SceneManager.Paused.toggle()
                    withAnimation {
                        shouldDisplayMenu.toggle()
                    }
                }
                
                // TODO: Certain keys (like shift) aren't detected:
                InputManager.HandleKeyPressedDebounced(keyCode: .y) {
                    withAnimation {
                        shouldDisplayGameStats.toggle()
                    }
                }
            }
        }
     }
    
    func getViewSize(geometrySize: CGSize) -> CGSize {
        if geometrySize.width > 0 && geometrySize.height > 0 {
            return geometrySize
        } else {
            return minViewSize
        }
    }
}

struct MacGameUIView_Previews: PreviewProvider {
    static var previews: some View {
        MacGameUIView()
    }
}
