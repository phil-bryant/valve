// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ValveProvisioningApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ValveProvisioningApp", targets: ["ValveProvisioningApp"]),
        .library(name: "ValveDomain", targets: ["ValveDomain"]),
        .library(name: "ValveNetworking", targets: ["ValveNetworking"]),
        .library(name: "ValveSecurity", targets: ["ValveSecurity"]),
        .library(name: "ValveFeatures", targets: ["ValveFeatures"])
    ],
    targets: [
        .target(name: "ValveDomain"),
        .target(name: "ValveNetworking", dependencies: ["ValveDomain"]),
        .target(name: "ValveSecurity", dependencies: ["ValveDomain"]),
        .target(name: "ValveFeatures", dependencies: ["ValveDomain", "ValveNetworking", "ValveSecurity"]),
        .executableTarget(name: "ValveProvisioningApp", dependencies: ["ValveFeatures"]),
        .testTarget(name: "ValveDomainTests", dependencies: ["ValveDomain"]),
        .testTarget(name: "ValveNetworkingTests", dependencies: ["ValveNetworking", "ValveDomain"])
    ]
)
