//
//  MetalHUDToggle.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/10/26.
//

// SwiftUI's switch toggle style is unavailable on tvOS.
#if !os(tvOS)

import SwiftUI

struct MetalHUDToggle: View {
    @Binding var hudEnabled: Bool
    
    var body: some View {
        Toggle("Enable Metal HUD", isOn: $hudEnabled)
            .toggleStyle(.switch)
            .onChange(of: hudEnabled) { _, newValue in
                MetalPerformanceHUD.setEnabled(newValue)
            }
    }
}

#Preview {
    MetalHUDToggle(hudEnabled: .constant(false))
}

#endif
