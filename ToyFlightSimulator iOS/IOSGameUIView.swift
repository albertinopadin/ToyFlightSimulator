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
    
    @State private var throttle: Float = 0.0
    @GestureState private var joystickPosition: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                IOSMetalViewWrapper(viewSize: geometry.size,
                                    refreshRate: framesPerSecond)
//                IOSMetalViewWrapper(viewSize: UIScreen.main.bounds.size,
//                                    refreshRate: framesPerSecond)
                
                Button("Zero Motion Device") {
                    print("Pressed Zero")
                    InputManager.ZeroMotionDevice()
                }
                .padding()
                .foregroundColor(.green)
                .background(.white)
                .clipShape(Capsule())
                .position(x: 120, y: 70)
                
                Slider(value: $throttle, label: {
                    Label("Throttle", systemImage: "airplane")
                }, minimumValueLabel: {
                    Text("Idle")
                        .rotationEffect(Angle(degrees: 90))
                }, maximumValueLabel: {
                    Text("Max")
                        .rotationEffect(Angle(degrees: 90))
                })
                .background(.gray.opacity(0.25))
                .rotationEffect(Angle(degrees: -90))
                .frame(width: 200, height: 100)
                .position(x: 120, y: geometry.size.height - 100)
                .onChange(of: throttle) { newValue in
                    print("Throttle changed: \(newValue)")
                    InputManager.SetContinuous(command: .MoveFwd, value: throttle)
                }
                
                Circle()
                    .fill(.gray.opacity(0.5))
                    .frame(width: 50, height: 50)
                    .position(x: geometry.size.width - 120, y: geometry.size.height - 100)
                    .offset(joystickPosition)
                    .gesture(
                        DragGesture().updating($joystickPosition) { value, state, transaction in
                            state = value.translation
                        }
                    )
                    .onChange(of: joystickPosition) { newValue in
                        print("Joystick position changed: \(newValue)")
                        // Height / Width are flipped as we're in landscape:
                        InputManager.SetContinuous(command: .Pitch, value: Float(newValue.height / 100).clamped(to: -1...1))
                        InputManager.SetContinuous(command: .Roll, value: Float(newValue.width / 100).clamped(to: -1...1))
                    }
                
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
            .onAppear(perform: {
                print("On Appear geometry size: \(geometry.size)")
            })
            .onChange(of: geometry.size) { newSize in
                print("Geometry changed size: \(newSize)")
            }
        }
        .ignoresSafeArea()
        .onAppear(perform: {
            InputManager.ZeroMotionDevice()
            
            Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { _ in
                InputManager.handleKeyPressedDebounced(keyCode: .escape) {
                    toggleMenu()
                }
            }
            
            Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
                InputManager.ZeroMotionDevice()
                InputManager.useMotion = useMotionControl
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
