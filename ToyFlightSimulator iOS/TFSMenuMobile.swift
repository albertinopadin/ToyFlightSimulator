//
//  TFSMenuMobile.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/9/24.
//

import SwiftUI

struct TFSMenuMobile: View {
    @Binding var framesPerSecond: FPS
    @Binding var useMotionControl: Bool
    
    var viewSize: CGSize
    
    @State private var rendererType: RendererType = .TiledDeferred
    
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 25.0).overlay {
                Label("Menu", systemImage: "airplane")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .foregroundColor(.white)
                    .padding(10.0)
                
                GeometryReader { geometry in
                    VStack(spacing: 20) {
                        Text("Toy Flight Simulator")
                            .font(.largeTitle)
                        
                        HStack {
                            Text("Refresh Rate: ")
                                .padding()
                            
                            Picker("Refresh Rate: ", selection: $framesPerSecond) {
                                ForEach(FPS.allCases) { fps in
                                    Text("\(fps.rawValue)").tag(fps).padding()
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: geometry.size.width * 0.35)
                        }
                        
                        Toggle("Use Motion Control", isOn: $useMotionControl)
                            .frame(maxWidth: geometry.size.width * 0.35)
                            .padding()
                            .onChange(of: useMotionControl) { newValue in
                                InputManager.useMotion = newValue
                            }
                        
                        Button("Reset Scene", role: .destructive) {
                            print("Pressed SwiftUI Reset Scene button")
                            SceneManager.ResetScene()
                        }
                        .padding()
                        .foregroundColor(.red)
                    }
                    .frame(width: geometry.size.width - 10, height: geometry.size.height - 10, alignment: .top)
                    .foregroundColor(.white)
                    .padding(10)
                }
            }
            .frame(width: viewSize.width - (viewSize.width * 0.10),
                    height: viewSize.height - (viewSize.height * 0.10))                        .foregroundColor(.black.opacity(0.95))
            
        }
        .frame(width: viewSize.width,
               height: viewSize.height,
               alignment: .center)  // Setting full view size so animation isn't cut off
        .transition(.move(edge: .top))
        .zIndex(100)  // Setting zIndex so transition is always on top
    }
}

#Preview {
    TFSMenuMobile(framesPerSecond: Binding<FPS>.constant(.FPS_120),
                  useMotionControl: Binding<Bool>.constant(false),
                  viewSize: CGSize(width: 1920, height: 1080))
}
