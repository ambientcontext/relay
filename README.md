# 📡 Relay
### Zero-config HTTP server for instant site previews

Relay is a zero-config Swift-based command line tool that turns any folder into a live-reloading web server. It focuses on being fast and simple to use. Just run `relay` (optionally specifying a port and a directory) and Relay will spawn a local server for you to browse and preview that content. 

### Installation

To build from source and install locally:

```bash
git clone https://github.com/ambientcontext/relay.git
cd relay
swift build -c release
sudo cp .build/release/relay /usr/local/bin/
```

### Quick Start
```bash
# Usage
relay [<directory>] [-p <p>] [-d]

# Serve current directory on http://localhost:8080
relay                 

# Serve any folder or file
relay some_directory  

# run on a custom port
relay -p 3000

# disable Live Reload         
relay -d             
```

### Features

- **Live Reload** – automatic page refresh on file changes
- **Smart port selection** – automatically looks for next available if specified port is unavailable
- **Directory index** – clean file listing when no index available
- **Minimal logs** – concise, colorized output

### Requirements

- macOS 12+ or Linux
- Swift 6 (to build)
