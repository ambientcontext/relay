import NIO
import NIOHTTP1
import NIOPosix
import Foundation
import Darwin

final class HTTPServer {

	// MARK: - Properties
	
    private let directory: String
    private let port: Int
    private let liveReload: Bool
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    
	// MARK: - Public
	
    init(directory: String, port: Int, liveReload: Bool) {
        self.directory = directory
        self.port = port
        self.liveReload = liveReload
    }
    
    func start() async throws {
        let fileHandler = FileHandler(directory: directory, liveReload: liveReload)
        
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPHandler(fileHandler: fileHandler))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
        
        do {
            let channel = try await bootstrap.bind(host: "127.0.0.1", port: port).get()
            print("📡 \u{001B}[1mRelay\u{001B}[0m running at \u{001B}[36mhttp://localhost:\(port)\u{001B}[0m")
            
            if liveReload {
                print("   Live Reload: \u{001B}[32m✓ enabled\u{001B}[0m")
            } else {
                print("   Live Reload: \u{001B}[31m⤬ disabled\u{001B}[0m")
            }
            
            print("   Serving: \u{001B}[35m\(directory)\u{001B}[0m")
            
            // Disable terminal echo to prevent user input from messing up the display
            let oldTermios = disableTerminalEcho()
            defer {
                // Restore terminal settings on exit
                if let oldTermios = oldTermios {
                    restoreTerminalEcho(oldTermios)
                }
            }
            
            // Print newline and hide cursor
            print("\u{001B}[?25l", terminator: "")
            
            let pulseTask = Task {
                // Using 256-color mode for smoother gradients
                let phases = [
                    "\u{001B}[38;5;22m●\u{001B}[0m",   // very dark green
                    "\u{001B}[38;5;28m●\u{001B}[0m",   // dark green
                    "\u{001B}[38;5;34m●\u{001B}[0m",   // medium-dark green
                    "\u{001B}[38;5;40m●\u{001B}[0m",   // medium green
                    "\u{001B}[38;5;46m●\u{001B}[0m",   // bright green
                    "\u{001B}[38;5;40m●\u{001B}[0m",   // medium green
                    "\u{001B}[38;5;34m●\u{001B}[0m",   // medium-dark green
                    "\u{001B}[38;5;28m●\u{001B}[0m"    // dark green
                ]
                var index = 0
                
                while !Task.isCancelled {
                    // Carriage return to beginning of current line, then reprint with pulsing dot
                    print("\r   \(phases[index]) Press \u{001B}[90mCtrl+C\u{001B}[0m to stop", terminator: "")
                    fflush(stdout)
                    
                    index = (index + 1) % phases.count
                    try? await Task.sleep(nanoseconds: 150_000_000) // 0.3 seconds
                }
            }

            // After animation ends, print newline to move cursor down
            print()
            
            defer {
                pulseTask.cancel()
                print("\u{001B}[?25h") // Show cursor again
            }
            
            try await channel.closeFuture.get()
        } catch {
            if let bindError = error as? NIOCore.IOError, bindError.errnoCode == EADDRINUSE {
                let nextPort = port + 1
                print("⚠️ \u{001B}[33m\u{001B}[0m Port \(port) is in use, trying \(nextPort)...")
                let server = HTTPServer(directory: directory, port: nextPort, liveReload: liveReload)
                try await server.start()
            } else {
                throw error
            }
        }
    }
    
    deinit {
        try? group.syncShutdownGracefully()
    }
	
}

private final class HTTPHandler: ChannelInboundHandler, @unchecked Sendable {
	
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    
    private let fileHandler: FileHandler
    private var requestHead: HTTPRequestHead?
    
    init(fileHandler: FileHandler) {
        self.fileHandler = fileHandler
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        
        switch part {
        case .head(let head):
            requestHead = head
        case .body:
            break
        case .end:
            guard let head = requestHead else { return }
            handleRequest(head: head, context: context)
        }
    }
    
    private func handleRequest(head: HTTPRequestHead, context: ChannelHandlerContext) {
        let response = fileHandler.handleRequest(uri: head.uri)
        
        let responseHead = HTTPResponseHead(
            version: head.version,
            status: response.status,
            headers: response.headers
        )
        
        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
        
        if let body = response.body {
            let buffer = context.channel.allocator.buffer(bytes: body)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        }
        
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }
	
}

// MARK: - Terminal Control

private func disableTerminalEcho() -> termios? {
	
    var oldTermios = termios()
    if tcgetattr(STDIN_FILENO, &oldTermios) == 0 {
        var newTermios = oldTermios
        // Disable echo and canonical mode (line buffering)
        newTermios.c_lflag &= ~(UInt(ECHO) | UInt(ICANON))
        tcsetattr(STDIN_FILENO, TCSANOW, &newTermios)
        return oldTermios
    }
    return nil
	
}

private func restoreTerminalEcho(_ oldTermios: termios) {
	
    var termios = oldTermios
    tcsetattr(STDIN_FILENO, TCSANOW, &termios)
	
}
