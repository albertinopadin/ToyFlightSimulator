//
//  GameUIView.swift
//  ToyFlightSimulator macOS
//
//  Created by Albertino Padin on 7/30/23.
//

import SwiftUI

struct GameUIView: View {
    @State private var viewSize: CGSize = .zero
    private let minViewSize = CGSize(width: 640, height: 480)
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MetalViewWrapper(viewSize: getViewSize(geometrySize: viewSize))
                    .frame(minWidth: minViewSize.width, minHeight: minViewSize.height)
                
                HStack {
                    Text("Toy Flight Simulator")
                        .font(.largeTitle)
                    
                    Button("Pause") {
                        print("Pressed SwiftUI Pause button")
                        // TODO: Super mega hack for now, for testing:
                        (SceneManager.currentScene as? FlightboxScene)?.paused.toggle()
                    }
                    .background(.blue)
                    
                }
                .position(CGPoint(x: viewSize.width - 200, y: viewSize.height - 50))
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
