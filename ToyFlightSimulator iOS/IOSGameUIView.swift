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
    @State private var useMotionControl: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                IOSMetalViewWrapper(viewSize: geometry.size,
                                    refreshRate: framesPerSecond)
                
                Button("Zero Motion Device") {
                    print("Pressed Zero")
                    InputManager.ZeroMotionDevice()
                }
                .padding()
                .foregroundColor(.green)
                .background(.white)
                .clipShape(Capsule())
                .position(x: 120, y: 70)
                
                TFSTouchThrottle(viewSize: geometry.size)
                
                TFSTouchJoystick(viewSize: geometry.size)
                
                if shouldDisplayMenu {
                    TFSMenuMobile(framesPerSecond: $framesPerSecond,
                                  useMotionControl: $useMotionControl,
                                  viewSize: geometry.size)
                }
            }
            .onAppear(perform: {
                print("On Appear geometry size: \(geometry.size)")
            })
            .onChange(of: geometry.size) { oldSize, newSize in
                print("Geometry changed size: \(newSize)")
            }
        }
        .ignoresSafeArea()
        .onAppear(perform: {
            InputManager.ZeroMotionDevice()
            
            Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { _ in
                InputManager.HandleKeyPressedDebounced(keyCode: .escape) {
                    MainActor.assumeIsolated {
                        toggleMenu()
                    }
                }
            }
            
            Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
                MainActor.assumeIsolated {
                    InputManager.ZeroMotionDevice()
                    InputManager.useMotion = useMotionControl
                }
            }
        })
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
        SceneManager.Paused.toggle()
        withAnimation {
            shouldDisplayMenu.toggle()
        }
    }
    
    func showMenu(_ shouldDisplay: Bool) {
        SceneManager.Paused = shouldDisplay
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

extension CGSize {
    static func *(lhs: CGSize, scalar: Int) -> CGSize {
        let floatScalar = CGFloat(scalar)
        return CGSize(width: lhs.width * floatScalar, height: lhs.height * floatScalar)
    }
}

extension Comparable {
//    func clamp(min: Self, max: Self) -> Self {
//        return min(max(self, min), max)
//    }
    
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
