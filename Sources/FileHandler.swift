import Foundation
import NIOHTTP1

struct HTTPResponse {
    let status: HTTPResponseStatus
    let headers: HTTPHeaders
    let body: [UInt8]?
}

final class FileHandler: Sendable {
	
	// MARK: - Properties
	
    private let directory: String
    private let liveReload: Bool

    // Default index files to check in order
    private let defaultIndexFiles = [
        "index.html",
        "index.htm",
        "default.html",
        "default.htm",
        "home.html",
        "home.htm"
    ]
    
	// MARK: - Lifecycle
	
    init(directory: String, liveReload: Bool) {
        // Resolve the directory to its real path to ensure consistent comparison
        self.directory = (directory as NSString).resolvingSymlinksInPath
        self.liveReload = liveReload
    }
	
	// MARK: - Public
    
    func handleRequest(uri: String) -> HTTPResponse {
        // Handle special auto-reload check endpoint
        if uri.starts(with: "/__relay_check__") && liveReload {
            return handleReloadCheck(uri: uri)
        }
        
        let path = sanitizePath(uri)
        let fullPath = directory + path
        
        // Resolve to real path to prevent symlink escape
        let realPath = (fullPath as NSString).resolvingSymlinksInPath
        
        // Ensure the resolved path is still within our directory
        if !realPath.hasPrefix(directory) {
            return notFoundResponse()
        }
        
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: realPath) else {
            return notFoundResponse()
        }
        
        if attributes[.type] as? FileAttributeType == .typeDirectory {
            // Check for any default index file
            for indexFile in defaultIndexFiles {
                let indexPath = realPath + "/" + indexFile
                if FileManager.default.fileExists(atPath: indexPath) {
                    return serveFile(at: indexPath)
                }
            }
            // No index file found, show directory listing
            return serveDirectoryListing(at: realPath, relativePath: path)
        }
        
        return serveFile(at: realPath)
    }
	
	// MARK: - Private
    
    private func sanitizePath(_ uri: String) -> String {
        var path = uri
        
        // Decode URL encoding first
        path = path.removingPercentEncoding ?? path
        
        // Check for directory traversal attempts
        if path.contains("..") || path.contains("//") {
            return "/"
        }
        
        // Remove null bytes
        path = path.replacingOccurrences(of: "\0", with: "")
        
        if !path.hasPrefix("/") {
            path = "/" + path
        }
        
        if path.hasSuffix("/") {
            path.removeLast()
        }
        
        return path
    }
    
    private func serveFile(at path: String) -> HTTPResponse {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return notFoundResponse()
        }
        
        var headers = HTTPHeaders()
        headers.add(name: "Server", value: "Relay")
        headers.add(name: "Content-Type", value: contentType(for: path))
        headers.add(name: "Content-Length", value: String(data.count))
        headers.add(name: "X-Content-Type-Options", value: "nosniff")
        headers.add(name: "X-Frame-Options", value: "SAMEORIGIN")
        
        // Add Last-Modified header
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let modificationDate = attributes[.modificationDate] as? Date {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
            formatter.timeZone = TimeZone(identifier: "GMT")
            formatter.locale = Locale(identifier: "en_US_POSIX")
            headers.add(name: "Last-Modified", value: formatter.string(from: modificationDate))
        }
        
        var body = [UInt8](data)
        
        if liveReload && (path.hasSuffix(".html") || path.hasSuffix(".htm")) {
            if let modifiedBody = injectReloadScript(body) {
                body = modifiedBody
                headers.replaceOrAdd(name: "Content-Length", value: String(body.count))
            }
        }
        
        return HTTPResponse(status: .ok, headers: headers, body: body)
    }
    
    private func injectReloadScript(_ body: [UInt8]) -> [UInt8]? {
        guard let html = String(bytes: body, encoding: .utf8) else { return nil }
        
        let reloadScript = """
        <script>
        (function() {
            let lastCheck = Date.now();
            
            async function checkForChanges() {
                try {
                    // Check a special endpoint that monitors all files
                    const response = await fetch('/__relay_check__?t=' + lastCheck, { 
                        cache: 'no-cache'
                    });
                    
                    if (response.ok) {
                        const data = await response.json();
                        if (data.hasChanges) {
                            window.location.reload();
                        }
                        lastCheck = data.timestamp;
                    }
                } catch (e) {
                    // Fallback to checking the current page
                    try {
                        const response = await fetch(window.location.href, { 
                            method: 'HEAD',
                            cache: 'no-cache'
                        });
                        const currentModified = response.headers.get('Last-Modified');
                        if (currentModified && lastCheck && Date.parse(currentModified) > lastCheck) {
                            window.location.reload();
                        }
                    } catch (e2) {
                        console.error('Relay auto-reload check failed:', e2);
                    }
                }
            }
            
            // Initial check after a brief delay
            setTimeout(checkForChanges, 50);
            
            // Then check every 250ms for fast reload
            setInterval(checkForChanges, 250);
        })();
        </script>
        """
        
        let modifiedHTML: String
        if let bodyIndex = html.lowercased().range(of: "</body>") {
            modifiedHTML = html.replacingCharacters(in: bodyIndex, with: reloadScript + "</body>")
        } else if let htmlIndex = html.lowercased().range(of: "</html>") {
            modifiedHTML = html.replacingCharacters(in: htmlIndex, with: reloadScript + "</html>")
        } else {
            modifiedHTML = html + reloadScript
        }
        
        return Array(modifiedHTML.utf8)
    }
    
    private func handleReloadCheck(uri: String) -> HTTPResponse {
        // Extract timestamp from query string
        var lastCheckTime: TimeInterval = 0
        if let queryRange = uri.range(of: "?t=") {
            let timestampStr = String(uri[queryRange.upperBound...])
            lastCheckTime = Double(timestampStr) ?? 0
        }
        
        // Check if any file in the directory has been modified since lastCheckTime
        let hasChanges = checkForModifiedFiles(since: Date(timeIntervalSince1970: lastCheckTime / 1000))
        
        let response = [
            "hasChanges": hasChanges,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ] as [String : Any]
        
        let jsonData = try! JSONSerialization.data(withJSONObject: response)
        
        var headers = HTTPHeaders()
        headers.add(name: "Server", value: "Relay")
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Cache-Control", value: "no-cache, no-store, must-revalidate")
        
        return HTTPResponse(status: .ok, headers: headers, body: Array(jsonData))
    }
    
    private func checkForModifiedFiles(since date: Date) -> Bool {
        let fileManager = FileManager.default
        
        // Use enumerator to check all files recursively
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: directory),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        
        while let fileURL = enumerator.nextObject() as? URL {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                if let modDate = resourceValues.contentModificationDate,
                   modDate > date {
                    return true
                }
            } catch {
                continue
            }
        }
        
        return false
    }
    
    private func contentType(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        
        switch ext {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js", "mjs", "jsx", "ts", "tsx": return "application/javascript; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "ico": return "image/x-icon"
        case "webp": return "image/webp"
        case "txt", "text": return "text/plain; charset=utf-8"
        case "xml": return "application/xml; charset=utf-8"
        case "pdf": return "application/pdf"
        case "zip": return "application/zip"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        
        // Common text-based source code files
        case "swift", "py", "rb", "go", "rs", "java", "c", "cpp", "h", "hpp", "cs", "php", "sh", "bash", "zsh", "fish":
            return "text/plain; charset=utf-8"
        
        // Common config/markup files
        case "md", "markdown", "yml", "yaml", "toml", "ini", "cfg", "conf", "env":
            return "text/plain; charset=utf-8"
        
        // Web-related text files
        case "vue", "svelte", "astro":
            return "text/plain; charset=utf-8"
            
        // If no extension or unknown, try to detect if it's text
        default:
            if isLikelyTextFile(at: path) {
                return "text/plain; charset=utf-8"
            }
            return "application/octet-stream"
        }
    }
    
    private func isLikelyTextFile(at path: String) -> Bool {
        guard let fileHandle = FileHandle(forReadingAtPath: path) else { return false }
        defer { fileHandle.closeFile() }
        
        // Read first 512 bytes to check if it's text
        let data = fileHandle.readData(ofLength: 512)
        guard !data.isEmpty else { return false }
        
        // Check if the data contains only printable ASCII/UTF-8 characters
        if String(data: data, encoding: .utf8) != nil {
            // Successfully decoded as UTF-8, likely text
            return true
        }
        
        // Check for binary signatures (images, executables, etc.)
        let bytes = [UInt8](data)
        
        // Common binary file signatures
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return false } // PNG
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return false } // JPEG
        if bytes.starts(with: [0x47, 0x49, 0x46]) { return false } // GIF
        if bytes.starts(with: [0x25, 0x50, 0x44, 0x46]) { return false } // PDF
        if bytes.starts(with: [0x50, 0x4B]) { return false } // ZIP
        if bytes.starts(with: [0x7F, 0x45, 0x4C, 0x46]) { return false } // ELF
        if bytes.starts(with: [0xCF, 0xFA, 0xED, 0xFE]) { return false } // Mach-O
        if bytes.starts(with: [0xCE, 0xFA, 0xED, 0xFE]) { return false } // Mach-O
        if bytes.starts(with: [0xCA, 0xFE, 0xBA, 0xBE]) { return false } // Mach-O Fat
        
        // Check for high percentage of non-printable characters
        let nonPrintableCount = bytes.filter { byte in
            // Allow common text characters
            return !(byte >= 32 && byte <= 126) && // Printable ASCII
                   byte != 9 && byte != 10 && byte != 13 // Tab, LF, CR
        }.count
        
        // If more than 30% non-printable, likely binary
        return Double(nonPrintableCount) / Double(bytes.count) < 0.3
    }
    
    private func serveDirectoryListing(at directoryPath: String, relativePath: String) -> HTTPResponse {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directoryPath) else {
            return notFoundResponse()
        }
        
        let sortedContents = contents.sorted { $0.lowercased() < $1.lowercased() }
        
        var fileItems: [(name: String, isDirectory: Bool, size: String, modified: String)] = []
        
        for item in sortedContents {
            let itemPath = directoryPath + "/" + item
            if let attributes = try? FileManager.default.attributesOfItem(atPath: itemPath) {
                let isDirectory = attributes[.type] as? FileAttributeType == .typeDirectory
                
                let size: String
                if isDirectory {
                    size = "-"
                } else if let fileSize = attributes[.size] as? Int64 {
                    size = formatFileSize(fileSize)
                } else {
                    size = "-"
                }
                
                let modified: String
                if let modDate = attributes[.modificationDate] as? Date {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .short
                    modified = formatter.string(from: modDate)
                } else {
                    modified = "-"
                }
                
                fileItems.append((name: item, isDirectory: isDirectory, size: size, modified: modified))
            }
        }
        
        let title = "Index of \(relativePath.isEmpty ? "/" : relativePath)"
        let parentLink = relativePath != "/" && !relativePath.isEmpty ? 
            "<tr><td colspan=\"3\"><a href=\"../\">../</a></td></tr>" : ""
        
        let rows = fileItems.map { item in
            let icon = item.isDirectory ? "📁" : getFileIcon(for: item.name)
            let name = item.isDirectory ? item.name + "/" : item.name
            let encodedName = item.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.name
            
            // Build the correct href based on current path
            let href: String
            if relativePath.isEmpty || relativePath == "/" {
                href = "/" + encodedName
            } else {
                href = relativePath + "/" + encodedName
            }
            
            return """
            <tr>
                <td><span class="icon">\(icon)</span> <a href="\(href)">\(name)</a></td>
                <td class="size">\(item.size)</td>
                <td class="modified">\(item.modified)</td>
            </tr>
            """
        }.joined(separator: "\n")
        
        let html = Template.directoryListing(title: title, parentLink: parentLink, rows: rows)
        
        var headers = HTTPHeaders()
        headers.add(name: "Server", value: "Relay")
        headers.add(name: "Content-Type", value: "text/html; charset=utf-8")
        
        return HTTPResponse(status: .ok, headers: headers, body: Array(html.utf8))
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(bytes)
        var unitIndex = 0
        
        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }
        
        if unitIndex == 0 {
            return "\(Int(size)) \(units[unitIndex])"
        } else {
            return String(format: "%.1f %@", size, units[unitIndex])
        }
    }
    
    private func getFileIcon(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        
        switch ext {
        case "html", "htm": return "🌐"
        case "css": return "🎨"
        case "js": return "📜"
        case "json": return "📋"
        case "png", "jpg", "jpeg", "gif", "svg", "webp": return "🖼"
        case "txt", "md": return "📄"
        case "pdf": return "📕"
        case "zip", "tar", "gz": return "📦"
        case "mp3", "wav", "m4a": return "🎵"
        case "mp4", "mov", "avi": return "🎬"
        case "swift": return "🦉"
        case "py": return "🐍"
        default: return "📄"
        }		
    }
    
    private func notFoundResponse() -> HTTPResponse {
        var headers = HTTPHeaders()
        headers.add(name: "Server", value: "Relay")
        headers.add(name: "Content-Type", value: "text/html; charset=utf-8")
        
        let html = Template.notFoundPage()
        
        return HTTPResponse(status: .notFound, headers: headers, body: Array(html.utf8))
    }
	
}
