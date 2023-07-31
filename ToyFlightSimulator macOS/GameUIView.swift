//
//  GameUIView.swift
//  ToyFlightSimulator macOS
//
//  Created by Albertino Padin on 7/30/23.
//

import SwiftUI

struct GameUIView: View {
    @State private var viewSize: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MetalViewWrapper(viewSize: getViewSize(geometrySize: viewSize))
                
                HStack {
                    Text("Toy Flight Simulator")
                        .font(.largeTitle)
                    
                    Button("Pause") {
                        print("Pressed SwiftUI Pause button")
                    }
                    .background(.blue)
                    .tint(.blue)
                    
                }
                .position(CGPoint(x: viewSize.width - 200, y: viewSize.height - 50))
            }
            .onAppear {
                viewSize = getViewSize(geometrySize: viewSize)
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
            return CGSize(width: 3840, height: 2160)
        }
    }
}

struct GameUIView_Previews: PreviewProvider {
//    static var previewSize = CGSize(width: 1920, height: 1080)
    static var previews: some View {
//        GameUIView(viewSize: previewSize)
        GameUIView()
    }
}
