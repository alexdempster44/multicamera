// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "multicamera",
  platforms: [
    .iOS("13.0")
  ],
  products: [
    .library(name: "multicamera", targets: ["multicamera"])
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework")
  ],
  targets: [
    .target(
      name: "multicamera",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework")
      ],
      resources: [
        .process("Resources")
      ]
    )
  ]
)
