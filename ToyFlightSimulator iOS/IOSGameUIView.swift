//
//  IOSGameUIView.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 8/5/23.
//

import SwiftUI

struct IOSGameUIView: View {
    @State private var shouldDisplayMenu: Bool = false
    @State private var framesPerSecond: FPS = .FPS_120
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                IOSMetalViewWrapper(viewSize: geometry.size,
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
                        .frame(width: geometry.size.width - (geometry.size.width * 0.10),
                                height: geometry.size.height - (geometry.size.height * 0.10))                        .foregroundColor(.black.opacity(0.95))
                        
                    }
                    .frame(width: geometry.size.width,
                           height: geometry.size.height,
                           alignment: .center)  // Setting full view size so animation isn't cut off
                    .transition(.move(edge: .top))
                    .zIndex(100)  // Setting zIndex so transition is always on top
                }
            }
            .onAppear {
                print("On Appear geometry size: \(geometry.size)")
            }
            .onChange(of: geometry.size) { newSize in
                print("Geometry changed size: \(newSize)")
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { _ in
                InputManager.handleKeyPressedDebounced(keyCode: .escape) {
                    toggleMenu()
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 100)
                .onEnded { drag in
                    let delta = drag.location - drag.startLocation
                    if delta.y > 100 {
                        showMenu(true)
                    }
                    if delta.y < -100 {
                        showMenu(false)
                    }
                }
        )
     }
    
    // TODO: Figure out how to combine toggleMenu and showMenu into single function:
    func toggleMenu() {
        SceneManager.paused.toggle()
        withAnimation {
            shouldDisplayMenu.toggle()
        }
    }
    
    func showMenu(_ shouldDisplay: Bool) {
        SceneManager.paused = shouldDisplay
        withAnimation {
            shouldDisplayMenu = shouldDisplay
        }
    }
}

struct IOSGameUIView_Previews: PreviewProvider {
    static var previews: some View {
        IOSGameUIView()
    }
}

extension CGPoint {
    static func -(lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        return CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
}

