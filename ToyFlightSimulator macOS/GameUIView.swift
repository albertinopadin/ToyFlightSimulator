//
//  GameUIView.swift
//  ToyFlightSimulator macOS
//
//  Created by Albertino Padin on 7/30/23.
//

import SwiftUI

struct GameUIView: View {
    private let minViewSize = CGSize(width: 640, height: 480)
    
    @State private var viewSize: CGSize = .zero
    @State private var shouldDisplayMenu: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MetalViewWrapper(viewSize: getViewSize(geometrySize: viewSize))
                
                if shouldDisplayMenu {
                    HStack {
                        Text("Toy Flight Simulator")
                            .font(.largeTitle)

                        Button("Pause") {
                            print("Pressed SwiftUI Pause button")
                            SceneManager.paused.toggle()
                        }
                        .background(.blue)
                    }
                    .position(CGPoint(x: viewSize.width - 200, y: viewSize.height - 50))
                    .transition(.move(edge: .bottom))
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

struct GameUIView_Previews: PreviewProvider {
    static var previews: some View {
        GameUIView()
    }
}
