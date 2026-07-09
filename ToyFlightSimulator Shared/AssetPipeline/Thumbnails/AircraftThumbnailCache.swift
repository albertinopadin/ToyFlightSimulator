//
//  AircraftThumbnailCache.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/9/26.
//
//  PNG disk cache under Caches/<bundle-id>/AircraftThumbnails/. Filenames are
//  "<case>-<key16>.png"; a changed key regenerates and prunes the old file.
//  Caches may be purged by the OS -- that's fine, we just regenerate.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum AircraftThumbnailCache {
    static func directory() -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "ToyFlightSimulator",
                                    isDirectory: true)
            .appendingPathComponent("AircraftThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func fileURL(caseName: String, key: String) -> URL? {
        directory()?.appendingPathComponent("\(caseName)-\(key.prefix(16)).png")
    }

    static func load(caseName: String, key: String) -> CGImage? {
        guard let url = fileURL(caseName: caseName, key: key),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Writes the PNG and removes older generations for the same aircraft.
    static func store(_ image: CGImage, caseName: String, key: String) {
        guard let url = fileURL(caseName: caseName, key: key),
              let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                                UTType.png.identifier as CFString,
                                                                1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        pruneStaleFiles(caseName: caseName, keeping: url.lastPathComponent)
    }

    private static func pruneStaleFiles(caseName: String, keeping filename: String) {
        guard let dir = directory(),
              let contents = try? FileManager.default.contentsOfDirectory(at: dir,
                                                                          includingPropertiesForKeys: nil)
        else { return }
        for file in contents
        where file.lastPathComponent.hasPrefix("\(caseName)-")
            && file.lastPathComponent != filename {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
