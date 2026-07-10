//
//  TFSMenu.swift
//  ToyFlightSimulator macOS
//
//  Created by Albertino Padin on 9/9/24.
//

import SwiftUI

struct TFSMenu: View {
    @Binding var framesPerSecond: FPS
    @Binding var rendererType: RendererType
    @Binding var volume: Float
    @Binding var aircraftType: AircraftType
    @Binding var hudEnabled: Bool
    @Binding var maxAnisotropy: MaxAnisotropy

    let thumbnailStore: AircraftThumbnailStore

    var viewSize: CGSize
    
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
                        
                        RefreshRatePicker(framesPerSecond: $framesPerSecond)
                            .frame(maxWidth: geometry.size.width * 0.35)
                        
                        VolumeSlider(volume: $volume)
                            .frame(maxWidth: geometry.size.width * 0.35)
                        
                        RendererPicker(rendererType: $rendererType)
                            .frame(maxWidth: geometry.size.width * 0.35)
                        
                        AnisotropyPicker(maxAnisotropy: $maxAnisotropy)
                            .frame(maxWidth: geometry.size.width * 0.35)
                        
                        MetalHUDToggle(hudEnabled: $hudEnabled)
                            .frame(maxWidth: geometry.size.width * 0.35)
                        
                        AircraftGridPicker(selection: $aircraftType,
                                           thumbnailStore: thumbnailStore)
                            .frame(maxWidth: geometry.size.width * 0.6)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .onChange(of: aircraftType) {
                                SceneManager.SetPlayerAircraft(aircraftType)
                            }
                        
                        ResetSceneButton()
                        
                        Spacer()
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
    TFSMenu(framesPerSecond: Binding<FPS>.constant(.FPS_120),
            rendererType: Binding<RendererType>.constant(.TiledDeferred),
            volume: Binding<Float>.constant(15.0),
            aircraftType: Binding<AircraftType>.constant(.f22),
            hudEnabled: Binding<Bool>.constant(false),
            maxAnisotropy: Binding<MaxAnisotropy>.constant(.x8),
            thumbnailStore: AircraftThumbnailStore(),
            viewSize: CGSize(width: 1920, height: 1080))
}
