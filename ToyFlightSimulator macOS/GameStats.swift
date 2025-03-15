//
//  GameStats.swift
//  ToyFlightSimulator macOS
//
//  Created by Albertino Padin on 9/9/24.
//

import SwiftUI

struct GameStats: View {
    @ObservedObject var gameStatsMgr = GameStatsManager.sharedInstance
    
    var viewSize: CGSize
    
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 15.0).overlay {
                Label("Game Stats", systemImage: "airplane")
                    .frame(maxWidth: .infinity,
                           maxHeight: .infinity,
                           alignment: .top)
                    .foregroundColor(.white)
                    .padding(10.0)
                
                VStack {
                    Text("Aspect Ratio: \(String(format: "%.2f", Renderer.AspectRatio))")
                        .foregroundColor(.white)
                        .padding(EdgeInsets(top: 30,
                                            leading: 5,
                                            bottom: 5,
                                            trailing: 5))
                    
                    Text("FPS: \(String(format: "%.2f", gameStatsMgr.rollingAverageFPS))")
                        .foregroundColor(.white)
                        .padding(5)
                    
                    Text("Memory: \(gameStatsMgr.memoryFootprint())")
                        .foregroundColor(.white)
                        .padding(5)
                    
                    Text("Frames Rendered: \(gameStatsMgr.framesRendered)")
                        .foregroundColor(.white)
                        .padding(5)
                    
                    Text("Scene Updates: \(gameStatsMgr.sceneUpdates)")
                        .foregroundColor(.white)
                        .padding(5)
                    
                    Spacer()
                }
                .padding(10)
            }
            .frame(width: 200,
                   height: 100,
                   alignment: .topTrailing)
            .padding(.top, 80)
            .padding(.trailing, 10)
            .foregroundColor(.black.opacity(0.80))
        }
        .frame(width: viewSize.width,
               height: viewSize.height,
               alignment: .topTrailing)
        .transition(.move(edge: .trailing))
        .zIndex(90)
    }
}

#Preview {
    GameStats(viewSize: CGSize(width: 1920, height: 1080))
}
