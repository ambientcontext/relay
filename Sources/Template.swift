import Foundation

struct Template {
	
    static let baseStyles = """
        body {
            font-family: system-ui, -apple-system, sans-serif;
            margin: 0;
            padding: 20px 40px;
            background: #f5f5f5;
            color: #333;
        }
        h1 {
            color: #333;
            border-bottom: 1px solid #ddd;
            padding-bottom: 10px;
        }
        
        @media (prefers-color-scheme: dark) {
            body {
                background: #1a1a1a;
                color: #e0e0e0;
            }
            h1 {
                color: #e0e0e0;
                border-bottom-color: #444;
            }
        }
        """
    
    static let directoryListingStyles = """
        \(baseStyles)
        table {
            width: 100%;
            background: white;
            border-radius: 8px;
            box-shadow: 0 2px 12px rgba(0,0,0,0.06);
            border-collapse: collapse;
            margin-top: 20px;
            overflow: hidden;
        }
        th, td {
            text-align: left;
            padding: 12px 16px;
            border-bottom: 1px solid #eee;
        }
        th {
            background: #f8f8f8;
            font-weight: 600;
            color: #666;
        }
        tbody tr:last-child td {
            border-bottom: none;
        }
        tbody tr {
            cursor: pointer;
        }
        tbody tr:hover {
            background: #f9f9f9;
        }
        a {
            color: #0066cc;
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
        .icon {
            font-size: 1.2em;
            vertical-align: middle;
            margin-right: 4px;
        }
        .size, .modified {
            color: #666;
            font-size: 0.9em;
        }
        .size {
            text-align: right;
            width: 100px;
        }
        .modified {
            text-align: right;
            width: 200px;
        }
        
        @media (prefers-color-scheme: dark) {
            table {
                background: #2a2a2a;
                box-shadow: 0 2px 12px rgba(0,0,0,0.2);
            }
            th, td {
                border-bottom-color: #444;
            }
            th {
                background: #333;
                color: #aaa;
            }
            tbody tr:hover {
                background: #333;
            }
            a {
                color: #4db8ff;
            }
            .size, .modified {
                color: #999;
            }
        }
        """
    
    static let errorPageStyles = """
        \(baseStyles)
        p { color: #666; }
        
        @media (prefers-color-scheme: dark) {
            p { color: #999; }
        }
        """
    
    static func directoryListing(
        title: String,
        parentLink: String,
        rows: String
    ) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <title>\(title)</title>
            <style>
                \(directoryListingStyles)
            </style>
        </head>
        <body>
            <h1>\(title)</h1>
            <table>
                <thead>
                    <tr>
                        <th>Name</th>
                        <th class="size">Size</th>
                        <th class="modified">Modified</th>
                    </tr>
                </thead>
                <tbody>
                    \(parentLink)
                    \(rows)
                </tbody>
            </table>
            <script>
                // Make table rows clickable
                document.addEventListener('DOMContentLoaded', function() {
                    const rows = document.querySelectorAll('tbody tr');
                    rows.forEach(row => {
                        const link = row.querySelector('a');
                        if (link) {
                            row.addEventListener('click', function(e) {
                                // Don't interfere if clicking directly on the link
                                if (e.target.tagName !== 'A') {
                                    window.location.href = link.href;
                                }
                            });
                        }
                    });
                });
            </script>
        </body>
        </html>
        """
    }
    
    static func notFoundPage() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <title>404 Not Found</title>
            <style>
                \(errorPageStyles)
            </style>
        </head>
        <body>
            <h1>404 Not Found</h1>
            <p>The requested file was not found.</p>
        </body>
        </html>
        """
    }
	
}
