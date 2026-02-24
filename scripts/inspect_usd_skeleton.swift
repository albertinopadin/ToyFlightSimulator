//
//  inspect_usd_skeleton.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/24/26.
//

import Foundation
import ModelIO

func inspectSkeleton(_ path: String) {
    print("Inspecting skeleton of asset at path: \(path)")
    let url = URL(fileURLWithPath: path)
    let asset = MDLAsset(url: url)

    print("Asset object count: \(asset.count)")
    for i in 0..<asset.count {
        let object = asset.object(at: i)
        walkObject(object, depth: 0)
    }
}

func walkObject(_ object: MDLObject, depth: Int) {
    let indent = String(repeating: "  ", count: depth)
    print("\(indent)[\(type(of: object))] \(object.name)")

    if let skeleton = object as? MDLSkeleton {
        print("\(indent)  Joint paths: \(skeleton.jointPaths)")
    }

    for i in 0..<object.components.count {
        let component = object.components[i]
        print("\(indent)  Component: \(type(of: component))")
        if let animBind = component as? MDLAnimationBindComponent {
            print("\(indent)    Skeleton: \(animBind.skeleton?.name ?? "nil")")
            print("\(indent)    Joint paths: \(animBind.skeleton?.jointPaths ?? [])")
            if let animation = animBind.jointAnimation as? MDLPackedJointAnimation {
                print("\(indent)    Animation joint paths: \(animation.jointPaths)")
            }
        }
    }

    let children = object.children.objects
    for case let child in children {
        walkObject(child, depth: depth + 1)
    }
}

let args = CommandLine.arguments.dropFirst()
if args.isEmpty {
    fputs("Usage: inspect_usd_skeleton <usdc-path> [<usdc-path> ...]\n", stderr)
    exit(1)
}

for arg in args { inspectSkeleton(arg) }
