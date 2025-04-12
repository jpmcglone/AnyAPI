// swift-tools-version: 5.10

import PackageDescription

let package = Package(
  name: "AnyAPI",
  platforms: [
    .iOS(.v14),
    .macOS(.v11)
  ],
  products: [
    .library(
      name: "AnyAPI",
      targets: ["AnyAPI"]
    ),
  ],
  dependencies: [
    .package(
      url: "https://github.com/Alamofire/Alamofire.git",
      from: "5.10.2"
    )
  ],
  targets: [
    .target(
      name: "AnyAPI",
      dependencies: [
        .product(name: "Alamofire", package: "Alamofire")
      ]
    ),
    .testTarget(
      name: "AnyAPITests",
      dependencies: ["AnyAPI"]
    ),
  ]
)
