//
//  GameUIView.swift
//  ToyFlightSimulator macOS
//
//  Created by Albertino Padin on 7/30/23.
//

import SwiftUI

struct GameUIView: View {
    var body: some View {
        VStack {
            Text("Toy Flight Simulator")
                .font(.largeTitle)
            
            MetalViewWrapper()
        }
    }
}

struct GameUIView_Previews: PreviewProvider {
    static var previews: some View {
        GameUIView()
    }
}
