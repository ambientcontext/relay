import ArgumentParser
import Foundation

@main
struct Relay: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "relay",
        abstract: "Zero-config HTTP server for instant site previews"
    )
    
    @Argument(help: "Directory to serve")
    var directory: String?
    
    @Option(name: .short, help: "Port to run the server on")
    var port: Int = 8080
    
    @Flag(name: .short, help: "Disable Live Reload on file changes")
    var disableLiveReload = false
    
    mutating func run() async throws {
        let resolvedDirectory = directory ?? FileManager.default.currentDirectoryPath
        let fullPath = URL(fileURLWithPath: resolvedDirectory).standardizedFileURL.path
        
        guard FileManager.default.fileExists(atPath: fullPath) else {
            throw ValidationError("Path does not exist: \(fullPath)")
        }
        
        let server = HTTPServer(directory: fullPath, port: port, liveReload: !disableLiveReload)
        try await server.start()
    }

}
