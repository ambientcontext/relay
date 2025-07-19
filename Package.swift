// swift-tools-version: 6.0.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "Relay",
	platforms: [
		.macOS(.v12)
	],
	products: [
		.executable(name: "relay", targets: ["Relay"])
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.1"),
		.package(url: "https://github.com/apple/swift-nio", from: "2.84.0"),
	],
	targets: [
		.executableTarget(
			name: "Relay",
			dependencies: [
				.product(name: "ArgumentParser", package: "swift-argument-parser"),
				.product(name: "NIO", package: "swift-nio"),
				.product(name: "NIOHTTP1", package: "swift-nio"),
			])
	]
)
