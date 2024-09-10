//
//  TFSMenu.swift
//  ToyFlightSimulator macOS
//
//  Created by Albertino Padin on 9/9/24.
//

import SwiftUI

struct TFSMenu: View {
    @Binding var framesPerSecond: FPS
    
    var viewSize: CGSize
    
    @State private var rendererType: RendererType = .TiledDeferred
    
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 25.0).overlay {
                Label("Menu", systemImage: "airplane")
                    .frame(maxWidth: .infinity,
                           maxHeight: .infinity,
                           alignment: .topLeading)
                    .foregroundColor(.white)
                    .padding(10.0)
                
                GeometryReader { geometry in
                    VStack(spacing: 20) {
                        Text("Toy Flight Simulator")
                            .font(.largeTitle)
                        
                        Picker("Refresh Rate: ", selection: $framesPerSecond) {
                            ForEach(FPS.allCases) { fps in
                                Text("\(fps.rawValue)").tag(fps).padding()
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: geometry.size.width * 0.35)
                        
                        Picker("Renderer: ", selection: $rendererType) {
                            ForEach(RendererType.allCases) { rendererType in
                                Text("\(rendererType.rawValue)").tag(rendererType).padding()
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: geometry.size.width * 0.35)
                        
                        Button("Reset Scene") {
                            print("Pressed SwiftUI Reset Scene button")
                            SceneManager.ResetScene()
                        }
                        .background(.blue)
                    }
                    .frame(width: geometry.size.width - 10,
                           height: geometry.size.height - 10,
                           alignment: .top)
                    .foregroundColor(.white)
                    .padding(10)
                }
            }
            .frame(width: viewSize.width - (viewSize.width * 0.10),
                   height: viewSize.height - (viewSize.height * 0.10))
            .foregroundColor(.black.opacity(0.95))
            
        }
        .frame(width: viewSize.width,
               height: viewSize.height,
               alignment: .center)  // Setting full view size so animation isn't cut off
        .transition(.move(edge: .top))
        .zIndex(100)  // Setting zIndex so transition is always on top
    }
}

#Preview {
    TFSMenu(framesPerSecond: Binding<FPS>.constant(.FPS_120), viewSize: CGSize(width: 1920, height: 1080))
}
