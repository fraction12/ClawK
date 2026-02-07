//
//  MemoryFilePreviewView.swift
//  ClawK
//
//  Preview view for memory files with Markdown rendering
//

import SwiftUI
import WebKit

struct MemoryFilePreviewView: View {
    @ObservedObject var viewModel: MemoryViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            if let file = viewModel.selectedFile {
                if viewModel.isLoadingContent {
                    ProgressView("Loading...")
                        .padding()
                } else {
                    // File preview
                    FilePreviewContent(
                        file: file,
                        content: viewModel.fileContent
                    )
                }
            } else {
                // No file selected
                NoFileSelectedView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - No File Selected

struct NoFileSelectedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("Select a File")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Choose a file from the sidebar to preview its contents.")
                .font(.ClawK.label)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - File Preview Content

struct FilePreviewContent: View {
    let file: MemoryFile
    let content: String
    @State private var showRaw = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.title2)
                    .foregroundColor(tierColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.ClawK.bodyBold)
                    
                    Text(file.path)
                        .font(.ClawK.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Toggle raw/rendered
                Picker("View", selection: $showRaw) {
                    Label("Rendered", systemImage: "eye").tag(false)
                    Label("Raw", systemImage: "chevron.left.forwardslash.chevron.right").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                
                // Open in editor button
                Button(action: openInEditor) {
                    Image(systemName: "square.and.pencil")
                }
                .help("Open in default editor")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            
            Divider()
            
            // Content
            if showRaw {
                RawContentView(content: content)
            } else {
                MarkdownWebView(content: content)
            }
        }
    }
    
    var tierColor: Color {
        switch file.tier {
        case .hot: return .red
        case .warm: return .orange
        case .cold: return .blue
        case .archive: return .gray
        }
    }
    
    func openInEditor() {
        let fullPath = "\(AppConfiguration.shared.workspacePath)/\(file.path)"
        NSWorkspace.shared.open(URL(fileURLWithPath: fullPath))
    }
}

// MARK: - Raw Content View

struct RawContentView: View {
    let content: String
    
    var body: some View {
        ScrollView {
            Text(content)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Markdown WebView

struct MarkdownWebView: NSViewRepresentable {
    let content: String
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = generateHTML(content: content)
        webView.loadHTMLString(html, baseURL: nil)
    }
    
    private func generateHTML(content: String) -> String {
        // Escape content for JavaScript
        let escaped = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css">
            <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
            <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
            <style>
                :root {
                    color-scheme: light dark;
                }
                
                * {
                    box-sizing: border-box;
                }
                
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
                    font-size: 14px;
                    line-height: 1.6;
                    color: var(--text-color);
                    background: transparent;
                    padding: 20px;
                    margin: 0;
                    max-width: 100%;
                }
                
                @media (prefers-color-scheme: dark) {
                    :root {
                        --text-color: #e6e6e6;
                        --code-bg: #1e1e1e;
                        --inline-code-bg: #2d2d2d;
                        --border-color: #404040;
                        --heading-color: #ffffff;
                        --link-color: #58a6ff;
                        --blockquote-color: #8b949e;
                        --blockquote-border: #3b434b;
                    }
                }
                
                @media (prefers-color-scheme: light) {
                    :root {
                        --text-color: #24292f;
                        --code-bg: #f6f8fa;
                        --inline-code-bg: #eff1f3;
                        --border-color: #d0d7de;
                        --heading-color: #1f2328;
                        --link-color: #0969da;
                        --blockquote-color: #656d76;
                        --blockquote-border: #d0d7de;
                    }
                }
                
                h1, h2, h3, h4, h5, h6 {
                    color: var(--heading-color);
                    margin-top: 24px;
                    margin-bottom: 16px;
                    font-weight: 600;
                    line-height: 1.25;
                }
                
                h1 { font-size: 2em; border-bottom: 1px solid var(--border-color); padding-bottom: 0.3em; }
                h2 { font-size: 1.5em; border-bottom: 1px solid var(--border-color); padding-bottom: 0.3em; }
                h3 { font-size: 1.25em; }
                h4 { font-size: 1em; }
                
                p { margin-top: 0; margin-bottom: 16px; }
                
                a {
                    color: var(--link-color);
                    text-decoration: none;
                }
                
                a:hover { text-decoration: underline; }
                
                code {
                    font-family: 'SF Mono', 'Menlo', 'Monaco', 'Courier New', monospace;
                    font-size: 85%;
                    background-color: var(--inline-code-bg);
                    padding: 0.2em 0.4em;
                    border-radius: 6px;
                }
                
                pre {
                    background-color: var(--code-bg);
                    border-radius: 8px;
                    padding: 16px;
                    overflow-x: auto;
                    margin: 16px 0;
                }
                
                pre code {
                    background: transparent;
                    padding: 0;
                    font-size: 13px;
                    line-height: 1.5;
                }
                
                blockquote {
                    margin: 0 0 16px 0;
                    padding: 0 1em;
                    color: var(--blockquote-color);
                    border-left: 4px solid var(--blockquote-border);
                }
                
                ul, ol {
                    margin-top: 0;
                    margin-bottom: 16px;
                    padding-left: 2em;
                }
                
                li + li { margin-top: 0.25em; }
                
                hr {
                    height: 0.25em;
                    padding: 0;
                    margin: 24px 0;
                    background-color: var(--border-color);
                    border: 0;
                    border-radius: 2px;
                }
                
                table {
                    border-collapse: collapse;
                    width: 100%;
                    margin-bottom: 16px;
                }
                
                th, td {
                    padding: 8px 13px;
                    border: 1px solid var(--border-color);
                }
                
                th {
                    font-weight: 600;
                    background-color: var(--inline-code-bg);
                }
                
                tr:nth-child(2n) {
                    background-color: var(--inline-code-bg);
                }
                
                img {
                    max-width: 100%;
                    height: auto;
                    border-radius: 8px;
                }
                
                /* Task lists */
                .task-list-item {
                    list-style-type: none;
                    margin-left: -1.5em;
                }
                
                .task-list-item input {
                    margin-right: 0.5em;
                }
            </style>
        </head>
        <body>
            <div id="content"></div>
            <script>
                marked.setOptions({
                    highlight: function(code, lang) {
                        if (lang && hljs.getLanguage(lang)) {
                            return hljs.highlight(code, { language: lang }).value;
                        }
                        return hljs.highlightAuto(code).value;
                    },
                    breaks: true,
                    gfm: true
                });
                
                const markdown = `\(escaped)`;
                document.getElementById('content').innerHTML = marked.parse(markdown);
            </script>
        </body>
        </html>
        """
    }
}
