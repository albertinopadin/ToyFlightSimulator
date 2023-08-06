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
    @State private var framesPerSecond: FPS = .FPS_120
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MacMetalViewWrapper(viewSize: getViewSize(geometrySize: viewSize),
                                    refreshRate: framesPerSecond)
                
                if shouldDisplayMenu {
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
                                    
                                    Picker("Refresh Rate: ", selection: $framesPerSecond) {
                                        ForEach(FPS.allCases) { fps in
                                            Text("\(fps.rawValue)").tag(fps).padding()
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(maxWidth: geometry.size.width * 0.35)
                                    
                                    Button("Reset Scene") {
                                        print("Pressed SwiftUI Reset Scene button")
                                        SceneManager.ResetScene()
                                    }
                                    .background(.blue)
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
            .onAppear {
                print("On Appear geometry size: \(geometry.size)")
                viewSize = getViewSize(geometrySize: geometry.size)
                print("On Appear viewSize: \(viewSize)")
            }
            .onChange(of: geometry.size) { newSize in
                viewSize = newSize
                print("Geometry changed size: \(newSize)")
            }
        }
        .frame(minWidth: minViewSize.width, minHeight: minViewSize.height)
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { _ in
                InputManager.handleKeyPressedDebounced(keyCode: .escape) {
                    SceneManager.paused.toggle()
                    withAnimation {
                        shouldDisplayMenu.toggle()
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
