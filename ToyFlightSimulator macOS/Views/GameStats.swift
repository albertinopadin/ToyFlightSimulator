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
        VStack(alignment: .leading, spacing: 6) {
            Label("Game Stats", systemImage: "airplane")
                .font(.headline)
                .padding(.bottom, 4)

            Text("Aspect Ratio: \(String(format: "%.2f", Renderer.AspectRatio))")
            Text("FPS: \(String(format: "%.2f", gameStatsMgr.rollingAverageFPS))")
            Text("Memory: \(gameStatsMgr.memoryFootprint())")
            Text("Frames Rendered: \(gameStatsMgr.frameCounter)")
            Text("Scene Updates: \(gameStatsMgr.sceneUpdates)")
            Text("Renderer: \(gameStatsMgr.currentRenderer.rawValue)")
        }
        .foregroundColor(.white)
        .monospacedDigit()
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 15.0)
                .fill(.black.opacity(0.80))
        )
        .padding(.top, 80)
        .padding(.trailing, 10)
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
