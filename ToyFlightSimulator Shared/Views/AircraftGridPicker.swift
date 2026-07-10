//
//  AircraftGridPicker.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/9/26.
//
//  X-Plane style aircraft picker: scrollable vertical grid, max 4 per row,
//  cards with a generated 3/4-view "photo", name top-left, blue selection.
//

// SwiftUI controlSize (used on the placeholder ProgressView) is unavailable on tvOS.
#if !os(tvOS)

import SwiftUI

struct AircraftGridPicker: View {
    @Binding var selection: AircraftType
    // Plain reference: @Observable stores are tracked by SwiftUI via body reads.
    let thumbnailStore: AircraftThumbnailStore

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AIRCRAFT")
                .font(.headline)
                .foregroundStyle(.secondary)

            ScrollView(.vertical) {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(AircraftType.allCases) { aircraft in
                        AircraftCard(aircraft: aircraft,
                                     image: thumbnailStore.thumbnails[aircraft],
                                     isSelected: selection == aircraft)
                            .onTapGesture { selection = aircraft }
                    }
                }
                .padding(2)   // room for the selection stroke
            }
        }
        .task { thumbnailStore.ensureAllThumbnails() }
    }
}

private struct AircraftCard: View {
    let aircraft: AircraftType
    let image: CGImage?
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(aircraft.rawValue)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(.white)

            Group {
                if let image {
                    Image(image, scale: 2, label: Text(aircraft.rawValue))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    ZStack {
                        Image(systemName: "airplane")
                            .font(.system(size: 36))
                            .foregroundStyle(.tertiary)
                        ProgressView()
                            .controlSize(.small)
                            .offset(y: 28)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.55)
                                 : Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : Color.white.opacity(0.15),
                              lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    AircraftGridPicker(selection: .constant(.f22_cgtrader),
                       thumbnailStore: AircraftThumbnailStore())
        .frame(width: 900, height: 420)
        .background(.black)
}

#endif
