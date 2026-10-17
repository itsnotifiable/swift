// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "Notifiable",
  platforms: [
    .iOS(.v16),
    .macOS(.v13),
  ],
  products: [
    .library(name: "Notifiable", targets: ["Notifiable"]),
  ],
  targets: [
    .target(name: "NotifiableCore"),
    .target(
      name: "Notifiable",
      dependencies: ["NotifiableCore"]
    ),
    .testTarget(
      name: "NotifiableCoreTests",
      dependencies: ["NotifiableCore"]
    ),
  ]
)
