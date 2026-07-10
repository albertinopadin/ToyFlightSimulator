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
    @Binding var volume: Float
    @Binding var aircraftType: AircraftType
    @Binding var hudEnabled: Bool
    @Binding var rendererType: RendererType
    @Binding var maxAnisotropy: MaxAnisotropy

    var viewSize: CGSize
    var onClose: () -> Void
    
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 25.0).overlay {
                Label("Menu", systemImage: "airplane")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .foregroundColor(.white)
                    .padding(10.0)
                
                
                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 20) {
                            Text("Toy Flight Simulator")
                                .font(.largeTitle)
                            
                            RefreshRatePicker(framesPerSecond: $framesPerSecond)
                                .frame(maxWidth: geometry.size.width * 0.80)
                            
                            Toggle("Use Motion Control", isOn: $useMotionControl)
                                .frame(maxWidth: geometry.size.width * 0.35)
                                .padding()
                                .onChange(of: useMotionControl) { oldValue, newValue in
                                    InputManager.useMotion = newValue
                                }

                            Toggle("Metal HUD", isOn: $hudEnabled)
                                .frame(maxWidth: geometry.size.width * 0.35)
                                .padding()
                                .onChange(of: hudEnabled) { oldValue, newValue in
                                    MetalPerformanceHUD.setEnabled(newValue)
                                }
                            
                            Button("Reset Scene", role: .destructive) {
                                print("Pressed SwiftUI Reset Scene button")
                                SceneManager.RequestResetScene()
                            }
                            .padding()
                            .foregroundColor(.red)
                            
                            VolumeSlider(volume: $volume)
                                .frame(maxWidth: geometry.size.width * 0.80)

                            RendererPicker(rendererType: $rendererType)
                                .frame(maxWidth: geometry.size.width * 0.80)

                            AnisotropyPicker(maxAnisotropy: $maxAnisotropy)
                                .frame(maxWidth: geometry.size.width * 0.80)

                            Picker("Aircraft: ", selection: $aircraftType) {
                                ForEach(AircraftType.allCases) { aircraftType in
                                    Text("\(aircraftType.rawValue)").tag(aircraftType).padding()
                                }
                            }
                            .pickerStyle(.automatic)
                            .frame(maxWidth: geometry.size.width * 0.35)
                            .onChange(of: aircraftType) {
                                SceneManager.SetPlayerAircraft(aircraftType)
                            }
                        }
                        .frame(width: geometry.size.width, alignment: .top)
                        .foregroundColor(.white)
                        .padding(10)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding(10)
                }
                .accessibilityLabel("Close menu")
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
                  volume: Binding<Float>.constant(15.0),
                  aircraftType: Binding<AircraftType>.constant(.f22),
                  hudEnabled: Binding<Bool>.constant(false),
                  rendererType: Binding<RendererType>.constant(.TiledMSAATessellated),
                  maxAnisotropy: Binding<MaxAnisotropy>.constant(.x8),
                  viewSize: CGSize(width: 1920, height: 1080),
                  onClose: {})
}
