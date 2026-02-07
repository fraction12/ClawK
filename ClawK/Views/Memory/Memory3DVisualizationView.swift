//
//  Memory3DVisualizationView.swift
//  ClawK
//
//  3D vector visualization of memory embeddings using Three.js
//

import SwiftUI
import WebKit

struct Memory3DVisualizationView: View {
    @ObservedObject var viewModel: MemoryViewModel
    @State private var webView: WKWebView?
    @State private var isReady = false
    @State private var spreadMultiplier: Double = 1.0
    @State private var loadError: String?
    
    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoadingEmbeddings {
                LoadingVisualizationView()
            } else if let error = loadError {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange.opacity(0.7))
                    
                    Text("Visualization Error")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(error)
                        .font(.ClawK.label)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Text("Memory files need embeddings to visualize.\nTry running a search first to index the data.")
                        .font(.ClawK.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("Retry") {
                        loadError = nil
                        viewModel.error = nil
                        viewModel.embeddingPoints = [] // Clear to allow reload
                        Task {
                            await viewModel.loadEmbeddings()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(40)
            } else if viewModel.embeddingPoints.isEmpty {
                EmptyVisualizationView()
            } else {
                // Main visualization
                ZStack {
                    ThreeJSVisualizationWebView(
                        points: viewModel.embeddingPoints,
                        selectedId: viewModel.selectedPointId,
                        searchQuery: viewModel.searchQuery,
                        onPointSelected: { pointId in
                            viewModel.selectPoint(pointId)
                        },
                        onReady: {
                            isReady = true
                        },
                        onSpreadChanged: { newValue in
                            spreadMultiplier = newValue
                        },
                        onError: { error in
                            loadError = error
                        },
                        webViewRef: $webView
                    )
                    
                    // Loading overlay while WebView initializes
                    if !isReady {
                        VStack {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Initializing 3D View...")
                                .font(.ClawK.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                    }
                    
                    // Overlay controls - bottom left
                    if isReady {
                        VStack {
                            Spacer()
                            
                            HStack {
                                SpreadControlPanel(
                                    spreadMultiplier: $spreadMultiplier,
                                    webView: webView
                                )
                                .padding()
                                
                                Spacer()
                                
                                VisualizationLegend()
                                    .padding()
                            }
                        }
                        
                        // Selected point info
                        if let selectedId = viewModel.selectedPointId,
                           let point = viewModel.embeddingPoints.first(where: { $0.id == selectedId }) {
                            VStack {
                                HStack {
                                    Spacer()
                                    SelectedPointCard(point: point)
                                        .padding()
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            // Sync any existing error state
            if let error = viewModel.error {
                loadError = error
            }
        }
        .task {
            // Only load if we don't have points and no error
            if viewModel.embeddingPoints.isEmpty && loadError == nil {
                await viewModel.loadEmbeddings()
            }
        }
        .onChange(of: viewModel.error) { _, error in
            if let error = error {
                loadError = error
            }
        }
    }
}

// MARK: - Spread Control Panel

struct SpreadControlPanel: View {
    @Binding var spreadMultiplier: Double
    var webView: WKWebView?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Spread slider
            HStack(spacing: 8) {
                Text("Spread:")
                    .font(.ClawK.caption)
                    .foregroundColor(.primary)
                
                Slider(value: $spreadMultiplier, in: 0.1...3.0, step: 0.1)
                    .frame(width: 120)
                    .onChange(of: spreadMultiplier) { _, newValue in
                        updateSpread(newValue)
                    }
                
                Text("\(Int(spreadMultiplier * 100))%")
                    .font(.ClawK.caption)
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
                    .foregroundColor(.primary)
            }
            
            // Preset buttons
            HStack(spacing: 6) {
                SpreadPresetButton(title: "Tight", value: 0.3, current: $spreadMultiplier) {
                    updateSpread(0.3)
                }
                
                SpreadPresetButton(title: "Normal", value: 1.0, current: $spreadMultiplier) {
                    updateSpread(1.0)
                }
                
                SpreadPresetButton(title: "Wide", value: 2.0, current: $spreadMultiplier) {
                    updateSpread(2.0)
                }
                
                SpreadPresetButton(title: "Max", value: 3.0, current: $spreadMultiplier) {
                    updateSpread(3.0)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
    
    private func updateSpread(_ value: Double) {
        spreadMultiplier = value
        webView?.evaluateJavaScript("updateSpread(\(value));", completionHandler: nil)
    }
}

struct SpreadPresetButton: View {
    let title: String
    let value: Double
    @Binding var current: Double
    let action: () -> Void
    
    var isActive: Bool {
        abs(current - value) < 0.05
    }
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ClawK.captionSmall)
                .fontWeight(isActive ? .semibold : .regular)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isActive ? Color.accentColor.opacity(0.3) : Color.clear)
                .foregroundColor(isActive ? .accentColor : .primary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Loading State

struct LoadingVisualizationView: View {
    @State private var dots = ""
    @State private var tickCount = 0
    
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Loading Memory Vectors\(dots)")
                .font(.ClawK.bodyBold)
            
            Text("Computing 3D positions from embeddings")
                .font(.ClawK.label)
                .foregroundColor(.secondary)
            
            if tickCount >= 6 { // 3 seconds (6 x 0.5s)
                Text("This may take a few seconds...")
                    .font(.ClawK.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(timer) { _ in
            // Animate dots
            if dots.count >= 3 {
                dots = ""
            } else {
                dots += "."
            }
            tickCount += 1
        }
    }
}

// MARK: - Empty State

struct EmptyVisualizationView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("No Embeddings Found")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Memory files need to be indexed to generate embeddings.\nRun a memory search to trigger indexing.")
                .font(.ClawK.label)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Legend

struct VisualizationLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            LegendItem(color: .red, label: "Hot")
            LegendItem(color: .orange, label: "Warm")
            LegendItem(color: .cyan, label: "Cold")
            LegendItem(color: Color(white: 0.8), label: "Archive")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            
            Text(label)
                .font(.ClawK.caption)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Selected Point Card

struct SelectedPointCard: View {
    let point: EmbeddingPoint
    
    var tierColor: Color {
        switch point.tier {
        case "hot": return .red
        case "warm": return .orange
        case "cold": return .cyan
        default: return .gray
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if point.isMemoryMdFile {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.yellow)
                        .font(.system(size: 14))
                } else {
                    Circle()
                        .fill(tierColor)
                        .frame(width: 12, height: 12)
                }
                
                Text(point.filename)
                    .font(.ClawK.bodyBold)
                    .lineLimit(1)
                
                if point.isMemoryMdFile {
                    Text("HUB")
                        .font(.ClawK.captionSmall)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.2))
                        .foregroundColor(.yellow)
                        .cornerRadius(4)
                }
            }
            
            Text(point.path)
                .font(.ClawK.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                if point.chunkIndex > 0 {
                    Label("Chunk \(point.chunkIndex + 1)", systemImage: "square.stack")
                        .font(.ClawK.caption)
                        .foregroundColor(.secondary)
                }
                
                if !point.isMemoryMdFile {
                    Label("\(Int(point.similarity * 100))% similar", systemImage: "link")
                        .font(.ClawK.caption)
                        .foregroundColor(point.similarity > 0.6 ? .yellow : .secondary)
                }
            }
            
            Divider()
            
            Text(point.text)
                .font(.ClawK.caption)
                .lineLimit(3)
                .foregroundColor(.secondary)
            
            // Token count with proper pluralization
            Text("\(point.tokens) \(point.tokens == 1 ? "token" : "tokens")")
                .font(.ClawK.captionSmall)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Three.js WebView

struct ThreeJSVisualizationWebView: NSViewRepresentable {
    let points: [EmbeddingPoint]
    let selectedId: String?
    let searchQuery: String
    let onPointSelected: (String) -> Void
    let onReady: () -> Void
    let onSpreadChanged: (Double) -> Void
    let onError: (String) -> Void
    @Binding var webViewRef: WKWebView?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "pointSelected")
        config.userContentController.add(context.coordinator, name: "vizReady")
        config.userContentController.add(context.coordinator, name: "spreadChanged")
        config.userContentController.add(context.coordinator, name: "vizError")
        
        // Allow loading from CDN
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        
        // Set navigation delegate for error handling
        webView.navigationDelegate = context.coordinator
        
        DispatchQueue.main.async {
            self.webViewRef = webView
        }
        
        let html = generateVisualizationHTML(points: points)
        webView.loadHTMLString(html, baseURL: nil)
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // Update selection
        if let selectedId = selectedId {
            webView.evaluateJavaScript("if(typeof selectPoint === 'function') selectPoint('\(selectedId)');", completionHandler: nil)
        }
        
        // Update search highlighting
        let escapedQuery = searchQuery
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\\", with: "\\\\")
        webView.evaluateJavaScript("if(typeof highlightSearch === 'function') highlightSearch('\(escapedQuery)');", completionHandler: nil)
    }
    
    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let parent: ThreeJSVisualizationWebView
        
        init(_ parent: ThreeJSVisualizationWebView) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "pointSelected", let pointId = message.body as? String {
                DispatchQueue.main.async {
                    self.parent.onPointSelected(pointId)
                }
            } else if message.name == "vizReady" {
                DispatchQueue.main.async {
                    self.parent.onReady()
                }
            } else if message.name == "spreadChanged" {
                if let spreadValue = message.body as? Double {
                    DispatchQueue.main.async {
                        self.parent.onSpreadChanged(spreadValue)
                    }
                } else if let spreadString = message.body as? String, let spreadValue = Double(spreadString) {
                    DispatchQueue.main.async {
                        self.parent.onSpreadChanged(spreadValue)
                    }
                }
            } else if message.name == "vizError", let errorMsg = message.body as? String {
                DispatchQueue.main.async {
                    self.parent.onError(errorMsg)
                }
            }
        }
        
        // WKNavigationDelegate for error handling
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.onError("Failed to load visualization: \(error.localizedDescription)")
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.onError("Navigation failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func generateVisualizationHTML(points: [EmbeddingPoint]) -> String {
        // Convert points to JSON
        let pointsJSON: String
        if let data = try? JSONEncoder().encode(points),
           let json = String(data: data, encoding: .utf8) {
            pointsJSON = json
        } else {
            pointsJSON = "[]"
        }
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body { overflow: hidden; background: transparent; }
                canvas { display: block; }
                
                #tooltip {
                    position: absolute;
                    background: rgba(0, 0, 0, 0.9);
                    color: white;
                    padding: 10px 14px;
                    border-radius: 8px;
                    font-family: -apple-system, sans-serif;
                    font-size: 12px;
                    pointer-events: none;
                    opacity: 0;
                    transition: opacity 0.15s;
                    max-width: 280px;
                    z-index: 1000;
                    border: 1px solid rgba(255, 255, 255, 0.1);
                }
                
                #tooltip.visible { opacity: 1; }
                
                #tooltip .filename {
                    font-weight: 600;
                    margin-bottom: 4px;
                    font-size: 13px;
                }
                
                #tooltip .tier {
                    font-size: 10px;
                    opacity: 0.7;
                    margin-bottom: 4px;
                }
                
                #tooltip .similarity {
                    font-size: 10px;
                    color: #ffd700;
                }
                
                #controls {
                    position: absolute;
                    bottom: 80px;
                    right: 20px;
                    display: flex;
                    flex-direction: column;
                    gap: 8px;
                }
                
                .control-btn {
                    position: relative;
                    width: 40px;
                    height: 40px;
                    border-radius: 8px;
                    border: none;
                    background: rgba(255, 255, 255, 0.1);
                    backdrop-filter: blur(10px);
                    color: white;
                    font-size: 18px;
                    cursor: pointer;
                    transition: background 0.2s, box-shadow 0.2s;
                }
                
                .control-btn:hover {
                    background: rgba(255, 255, 255, 0.2);
                }
                
                .control-btn.active {
                    background: rgba(255, 215, 0, 0.3);
                    box-shadow: 0 0 8px rgba(255, 215, 0, 0.4);
                }
                
                .control-btn.active::after {
                    content: '';
                    position: absolute;
                    inset: -2px;
                    border-radius: 10px;
                    border: 1px solid rgba(255, 215, 0, 0.5);
                    pointer-events: none;
                }
                
                #hub-info {
                    position: absolute;
                    top: 20px;
                    left: 20px;
                    background: rgba(0, 0, 0, 0.7);
                    color: white;
                    padding: 12px 16px;
                    border-radius: 8px;
                    font-family: -apple-system, sans-serif;
                    font-size: 12px;
                    backdrop-filter: blur(10px);
                }
                
                #hub-info .title {
                    font-weight: 600;
                    font-size: 14px;
                    color: #ffd700;
                    margin-bottom: 6px;
                }
                
                @media (prefers-color-scheme: light) {
                    .control-btn {
                        background: rgba(0, 0, 0, 0.1);
                        color: black;
                    }
                    .control-btn:hover {
                        background: rgba(0, 0, 0, 0.2);
                    }
                    #hub-info {
                        background: rgba(255, 255, 255, 0.9);
                        color: black;
                    }
                }
            </style>
        </head>
        <body>
            <div id="tooltip">
                <div class="filename"></div>
                <div class="tier"></div>
                <div class="similarity"></div>
            </div>
            
            <div id="hub-info">
                <div class="title">🧠 MEMORY.md Hub</div>
                <div id="hub-stats">Loading...</div>
            </div>
            
            <div id="controls">
                <button class="control-btn" onclick="resetCamera()" title="Reset View">↺</button>
                <button class="control-btn" onclick="toggleRotation()" title="Auto Rotate">⟳</button>
                <button class="control-btn" id="btn-connections" onclick="toggleConnections()" title="Toggle Connections">⚡</button>
                <button class="control-btn" onclick="focusMemoryMd()" title="Focus MEMORY.md">🧠</button>
            </div>
            
            <script>
                // Dynamic script loader with retry — loadHTMLString + CDN scripts
                // can race; DOMContentLoaded fires before <script src> completes.
                // We load scripts programmatically so we know exactly when they arrive.
                
                function loadScript(url, retries) {
                    retries = retries || 0;
                    return new Promise(function(resolve, reject) {
                        var s = document.createElement('script');
                        s.src = url;
                        s.onload = resolve;
                        s.onerror = function() {
                            if (retries < 2) {
                                console.warn('Retrying script load (' + (retries+1) + '): ' + url);
                                setTimeout(function() {
                                    loadScript(url, retries + 1).then(resolve).catch(reject);
                                }, 500);
                            } else {
                                reject(new Error('Failed to load: ' + url));
                            }
                        };
                        document.head.appendChild(s);
                    });
                }
                
                (async function() {
                    try {
                        await loadScript('https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js');
                        await loadScript('https://cdn.jsdelivr.net/npm/three@0.128.0/examples/js/controls/OrbitControls.js');
                    } catch (e) {
                        window.webkit.messageHandlers.vizError.postMessage(e.message);
                        return;
                    }
                    
                    if (typeof THREE === 'undefined') {
                        window.webkit.messageHandlers.vizError.postMessage('Three.js failed to load');
                        return;
                    }
                    if (typeof THREE.OrbitControls === 'undefined') {
                        window.webkit.messageHandlers.vizError.postMessage('OrbitControls failed to load');
                        return;
                    }
                    
                    console.log('All dependencies loaded, initializing...');
                    try {
                        initVisualization();
                    } catch (error) {
                        console.error('Visualization initialization error:', error);
                        window.webkit.messageHandlers.vizError.postMessage('Initialization error: ' + error.message);
                    }
                })();
                
                function initVisualization() {
                
                // Data
                const points = \(pointsJSON);
                let showConnections = true;
                let currentSpreadMultiplier = 1.0;
                
                // Find MEMORY.md points - helper matches Swift's isMemoryMdFile computed property
                // Check ALL possible field variations for MEMORY.md identification
                const isMemoryMdPoint = (p) => {
                    const path = (p.path || '').toLowerCase();
                    const file = (p.file || '').toLowerCase();
                    const filename = (p.filename || '').toLowerCase();
                    const fileName = (p.fileName || '').toLowerCase();
                    
                    return p.isMemoryMd === true || 
                           p.isMemoryMdFile === true ||
                           path === 'memory.md' || 
                           path.endsWith('/memory.md') ||
                           file === 'memory.md' ||
                           file.endsWith('/memory.md') ||
                           filename === 'memory.md' ||
                           fileName === 'memory.md';
                };
                
                // DEBUG: Log first 3 points to see actual data structure
                console.log('=== MEMORY.MD FILTER DEBUG ===');
                console.log('Total points:', points.length);
                console.log('First 3 points sample:', JSON.stringify(points.slice(0, 3).map(p => ({
                    id: p.id,
                    path: p.path,
                    file: p.file,
                    filename: p.filename,
                    fileName: p.fileName,
                    isMemoryMd: p.isMemoryMd,
                    isMemoryMdFile: p.isMemoryMdFile,
                    tier: p.tier,
                    x: p.x?.toFixed(3),
                    y: p.y?.toFixed(3),
                    z: p.z?.toFixed(3)
                })), null, 2));
                
                const memoryMdPoints = points.filter(p => isMemoryMdPoint(p));
                const otherPoints = points.filter(p => !isMemoryMdPoint(p));
                
                // ========================================
                // SIMILARITY CALCULATION (ACTUAL VECTOR MATH)
                // ========================================
                
                // Calculate cosine similarity between two vectors
                function cosineSimilarity(vecA, vecB) {
                    if (!vecA || !vecB || vecA.length !== vecB.length || vecA.length === 0) return 0;
                    const dotProduct = vecA.reduce((sum, a, i) => sum + a * vecB[i], 0);
                    const magA = Math.sqrt(vecA.reduce((sum, a) => sum + a * a, 0));
                    const magB = Math.sqrt(vecB.reduce((sum, b) => sum + b * b, 0));
                    if (magA === 0 || magB === 0) return 0;
                    return dotProduct / (magA * magB);
                }
                
                // Calculate Euclidean distance in 3D
                function euclideanDistance3D(p1, p2) {
                    const dx = (p1.x || 0) - (p2.x || 0);
                    const dy = (p1.y || 0) - (p2.y || 0);
                    const dz = (p1.z || 0) - (p2.z || 0);
                    return Math.sqrt(dx*dx + dy*dy + dz*dz);
                }
                
                // Fallback: Calculate similarity from 3D positions (inverse Euclidean distance)
                function calculateSimilarityFrom3D(point, memoryMdCenter) {
                    const distance = euclideanDistance3D(point, memoryMdCenter);
                    // Inverse distance normalized to 0-1 range
                    // Using sigmoid-like function: 1 / (1 + distance)
                    // Close points (distance ~0) -> similarity ~1
                    // Far points (distance ~2) -> similarity ~0.33
                    return 1 / (1 + distance);
                }
                
                // Calculate average position of MEMORY.md chunks (should be near 0,0,0)
                let memoryMdCenter = { x: 0, y: 0, z: 0 };
                if (memoryMdPoints.length > 0) {
                    memoryMdCenter.x = memoryMdPoints.reduce((sum, p) => sum + (p.x || 0), 0) / memoryMdPoints.length;
                    memoryMdCenter.y = memoryMdPoints.reduce((sum, p) => sum + (p.y || 0), 0) / memoryMdPoints.length;
                    memoryMdCenter.z = memoryMdPoints.reduce((sum, p) => sum + (p.z || 0), 0) / memoryMdPoints.length;
                }
                
                // Ensure all points have valid similarityToMemory
                // Uses actual data first, falls back to 3D distance calculation
                let calculatedCount = 0;
                let preExistingCount = 0;
                
                for (const point of otherPoints) {
                    const existingSimilarity = point.similarityToMemory;
                    
                    // Check if similarity is already calculated (not null/undefined/0)
                    if (existingSimilarity !== null && existingSimilarity !== undefined && existingSimilarity > 0.001) {
                        preExistingCount++;
                        // Already has valid similarity from backend (cosine similarity)
                        continue;
                    }
                    
                    // Fallback: Calculate from 3D positions
                    point.similarityToMemory = calculateSimilarityFrom3D(point, memoryMdCenter);
                    calculatedCount++;
                }
                
                console.log('=== SIMILARITY CALCULATION DEBUG ===');
                console.log('Pre-existing similarity values:', preExistingCount);
                console.log('Calculated from 3D positions:', calculatedCount);
                if (otherPoints.length > 0) {
                    const sims = otherPoints.map(p => p.similarityToMemory || 0);
                    console.log('Similarity range:', Math.min(...sims).toFixed(3), '-', Math.max(...sims).toFixed(3));
                    console.log('Average similarity:', (sims.reduce((a,b) => a+b, 0) / sims.length).toFixed(3));
                }
                console.log('=== END SIMILARITY DEBUG ===');
                
                console.log('MEMORY.md points found:', memoryMdPoints.length);
                if (memoryMdPoints.length > 0) {
                    console.log('MEMORY.md points details:', JSON.stringify(memoryMdPoints.map(p => ({
                        path: p.path,
                        isMemoryMd: p.isMemoryMd,
                        isMemoryMdFile: p.isMemoryMdFile,
                        tier: p.tier,
                        chunkIndex: p.chunkIndex,
                        x: p.x?.toFixed(3),
                        y: p.y?.toFixed(3),
                        z: p.z?.toFixed(3)
                    })), null, 2));
                }
                console.log('Other points (should NOT include MEMORY.md):', otherPoints.length);
                
                // Verify no MEMORY.md slipped through to otherPoints
                const leakedMemoryMd = otherPoints.filter(p => {
                    const path = (p.path || '').toLowerCase();
                    return path.includes('memory.md');
                });
                if (leakedMemoryMd.length > 0) {
                    console.error('ERROR: MEMORY.md leaked into otherPoints!', leakedMemoryMd.map(p => p.path));
                }
                console.log('=== END DEBUG ===');
                
                // Scene setup
                const scene = new THREE.Scene();
                const camera = new THREE.PerspectiveCamera(60, window.innerWidth / window.innerHeight, 0.1, 1000);
                camera.position.set(1.5, 1, 1.5);
                
                const renderer = new THREE.WebGLRenderer({ 
                    antialias: true, 
                    alpha: true 
                });
                renderer.setSize(window.innerWidth, window.innerHeight);
                renderer.setPixelRatio(window.devicePixelRatio);
                document.body.appendChild(renderer.domElement);
                
                // Controls
                const controls = new THREE.OrbitControls(camera, renderer.domElement);
                controls.enableDamping = true;
                controls.dampingFactor = 0.05;
                controls.autoRotate = true;
                controls.autoRotateSpeed = 0.3;
                controls.target.set(0, 0, 0); // Focus on center (MEMORY.md)
                
                // Lighting
                const ambientLight = new THREE.AmbientLight(0xffffff, 0.5);
                scene.add(ambientLight);
                
                const directionalLight = new THREE.DirectionalLight(0xffffff, 0.6);
                directionalLight.position.set(5, 5, 5);
                scene.add(directionalLight);
                
                // Point light at center for MEMORY.md glow
                const centerLight = new THREE.PointLight(0xffd700, 1, 3);
                centerLight.position.set(0, 0, 0);
                scene.add(centerLight);
                
                // Very subtle fog (reduced for better visibility)
                scene.fog = new THREE.FogExp2(0x000000, 0.15);
                
                // Background stars
                const starsGeometry = new THREE.BufferGeometry();
                const starPositions = [];
                for (let i = 0; i < 300; i++) {
                    starPositions.push(
                        (Math.random() - 0.5) * 8,
                        (Math.random() - 0.5) * 8,
                        (Math.random() - 0.5) * 8
                    );
                }
                starsGeometry.setAttribute('position', new THREE.Float32BufferAttribute(starPositions, 3));
                const starsMaterial = new THREE.PointsMaterial({ color: 0xffffff, size: 0.008, transparent: true, opacity: 0.4 });
                const starField = new THREE.Points(starsGeometry, starsMaterial);
                scene.add(starField);
                
                // Tier colors - brighter for visibility on dark background
                const tierColors = {
                    hot: 0xff4444,
                    warm: 0xffaa00,
                    cold: 0x00ddff,     // Bright cyan for visibility
                    archive: 0xcccccc   // Light gray for visibility
                };
                
                // Create spheres and connection lines
                const spheres = [];
                const pointData = new Map();
                const connectionLines = [];
                let memoryMdSphere = null;
                
                // K-nearest neighbors helper
                function findKNearestNeighbors(points, k = 5, maxDistance = 0.8) {
                    const connections = [];
                    const seen = new Set();
                    
                    for (let i = 0; i < points.length; i++) {
                        const p1 = points[i];
                        const distances = [];
                        
                        for (let j = 0; j < points.length; j++) {
                            if (i === j) continue;
                            const p2 = points[j];
                            const dx = p1.x - p2.x;
                            const dy = p1.y - p2.y;
                            const dz = p1.z - p2.z;
                            const dist = Math.sqrt(dx*dx + dy*dy + dz*dz);
                            if (dist < maxDistance) {
                                distances.push({ index: j, distance: dist });
                            }
                        }
                        
                        // Sort by distance and take k nearest
                        distances.sort((a, b) => a.distance - b.distance);
                        const nearest = distances.slice(0, k);
                        
                        for (const neighbor of nearest) {
                            // Create unique key for this connection
                            const key = i < neighbor.index ? `${i}-${neighbor.index}` : `${neighbor.index}-${i}`;
                            if (!seen.has(key)) {
                                seen.add(key);
                                connections.push({
                                    from: i,
                                    to: neighbor.index,
                                    distance: neighbor.distance
                                });
                            }
                        }
                    }
                    
                    return connections;
                }
                
                // Create SINGLE MEMORY.md hub sphere at center
                // We consolidate all MEMORY.md chunks into one visual representation
                if (memoryMdPoints.length > 0) {
                    console.log('Creating SINGLE MEMORY.md hub at center (0,0,0), consolidating', memoryMdPoints.length, 'chunks');
                    
                    // Use first chunk as representative
                    const point = memoryMdPoints[0];
                    const size = 0.08;
                    
                    const geometry = new THREE.SphereGeometry(size, 32, 32);
                    const material = new THREE.MeshPhongMaterial({ 
                        color: 0xffd700,
                        emissive: 0xffd700,
                        emissiveIntensity: 0.6,
                        shininess: 100,
                        specular: 0xffffff
                    });
                    
                    const sphere = new THREE.Mesh(geometry, material);
                    // CRITICAL: Place at center (0,0,0), NOT at embedding coordinates
                    sphere.position.set(0, 0, 0);
                    sphere.userData = { 
                        id: point.id, 
                        point: point,
                        originalColor: 0xffd700,
                        originalSize: size,
                        isMemoryMd: true,
                        chunkCount: memoryMdPoints.length  // Track how many chunks consolidated
                    };
                    
                    // Add glow layers
                    const glowGeometry = new THREE.SphereGeometry(size * 1.25, 32, 32);
                    const glowMaterial = new THREE.MeshBasicMaterial({
                        color: 0xffd700,
                        transparent: true,
                        opacity: 0.15
                    });
                    const glow = new THREE.Mesh(glowGeometry, glowMaterial);
                    sphere.add(glow);
                    
                    // Add subtle pulsing outer glow
                    const outerGlowGeometry = new THREE.SphereGeometry(size * 1.4, 16, 16);
                    const outerGlowMaterial = new THREE.MeshBasicMaterial({
                        color: 0xffd700,
                        transparent: true,
                        opacity: 0.08
                    });
                    const outerGlow = new THREE.Mesh(outerGlowGeometry, outerGlowMaterial);
                    sphere.add(outerGlow);
                    sphere.userData.outerGlow = outerGlow;
                    
                    memoryMdSphere = sphere;
                    
                    scene.add(sphere);
                    spheres.push(sphere);
                    
                    // Map ALL MEMORY.md chunk IDs to this single sphere
                    memoryMdPoints.forEach(p => {
                        pointData.set(p.id, sphere);
                    });
                    
                    console.log('MEMORY.md hub created at (0,0,0)');
                } else {
                    console.log('No MEMORY.md points found to create hub');
                }
                
                // Create other points (verified: no MEMORY.md)
                console.log('Creating', otherPoints.length, 'regular points (none should be MEMORY.md)');
                otherPoints.forEach((point, index) => {
                    // Double-check: skip any MEMORY.md that might have slipped through
                    if (isMemoryMdPoint(point)) {
                        console.error('SKIPPING leaked MEMORY.md at index', index, ':', point.path);
                        return;
                    }
                    
                    const color = tierColors[point.tier] || 0x888888;
                    const similarity = point.similarityToMemory || 0;
                    
                    // Size based on similarity + tokens
                    const baseSize = 0.015;
                    const simScale = similarity * 0.02;
                    const tokenScale = Math.min(point.tokens / 1000, 0.01);
                    const size = baseSize + simScale + tokenScale;
                    
                    const geometry = new THREE.SphereGeometry(size, 20, 20);
                    const material = new THREE.MeshPhongMaterial({ 
                        color: color,
                        emissive: color,
                        emissiveIntensity: 0.2 + similarity * 0.3,
                        shininess: 60,
                        specular: 0x333333
                    });
                    
                    const sphere = new THREE.Mesh(geometry, material);
                    sphere.position.set(point.x, point.y, point.z);
                    sphere.userData = { 
                        id: point.id, 
                        point: point,
                        originalColor: color,
                        originalSize: size,
                        isMemoryMd: false
                    };
                    
                    // Subtle glow based on similarity
                    if (similarity > 0.3) {
                        const glowGeometry = new THREE.SphereGeometry(size * 1.2, 12, 12);
                        const glowMaterial = new THREE.MeshBasicMaterial({
                            color: color,
                            transparent: true,
                            opacity: 0.12 + similarity * 0.08
                        });
                        const glow = new THREE.Mesh(glowGeometry, glowMaterial);
                        sphere.add(glow);
                    }
                    
                    scene.add(sphere);
                    spheres.push(sphere);
                    pointData.set(point.id, sphere);
                });
                
                // Create connection lines using k-nearest neighbors
                function createConnectionLines() {
                    // Clear existing lines
                    connectionLines.forEach(line => {
                        scene.remove(line);
                        if (line.geometry) line.geometry.dispose();
                        if (line.material) line.material.dispose();
                    });
                    connectionLines.length = 0;
                    
                    // Build points array with current positions
                    const pointPositions = spheres.map(sphere => ({
                        x: sphere.position.x,
                        y: sphere.position.y,
                        z: sphere.position.z,
                        userData: sphere.userData
                    }));
                    
                    // Find k-nearest neighbors
                    const k = Math.min(3, Math.max(1, Math.floor(points.length / 10)));
                    const connections = findKNearestNeighbors(pointPositions, k, 0.6);
                    
                    console.log('Creating', connections.length, 'connection lines');
                    
                    // Create lines for each connection
                    connections.forEach(conn => {
                        const sphere1 = spheres[conn.from];
                        const sphere2 = spheres[conn.to];
                        
                        if (!sphere1 || !sphere2) return;
                        
                        const lineGeometry = new THREE.BufferGeometry();
                        const positions = new Float32Array([
                            sphere1.position.x, sphere1.position.y, sphere1.position.z,
                            sphere2.position.x, sphere2.position.y, sphere2.position.z
                        ]);
                        lineGeometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
                        
                        // Line opacity based on distance (closer = more visible)
                        const opacity = Math.max(0.1, 0.5 - conn.distance * 0.5);
                        
                        // Color based on tier or similarity
                        const p1 = sphere1.userData.point;
                        const p2 = sphere2.userData.point;
                        let lineColor = 0x4488ff; // Default blue
                        
                        // Gold for connections involving MEMORY.md
                        if (p1.isMemoryMd || p2.isMemoryMd) {
                            lineColor = 0xffd700;
                        } else if (p1.tier === 'hot' || p2.tier === 'hot') {
                            lineColor = 0xff6644;
                        } else if (p1.tier === 'warm' || p2.tier === 'warm') {
                            lineColor = 0xffaa44;
                        }
                        
                        const lineMaterial = new THREE.LineBasicMaterial({
                            color: lineColor,
                            transparent: true,
                            opacity: opacity,
                            linewidth: 1
                        });
                        
                        const line = new THREE.Line(lineGeometry, lineMaterial);
                        line.userData = { fromIdx: conn.from, toIdx: conn.to, distance: conn.distance };
                        line.visible = showConnections;
                        scene.add(line);
                        connectionLines.push(line);
                    });
                    
                    // Also add radial lines from high-similarity points to MEMORY.md center
                    if (memoryMdSphere) {
                        otherPoints.forEach((point, idx) => {
                            const similarity = point.similarityToMemory || 0;
                            if (similarity > 0.3) {
                                const sphereIdx = memoryMdPoints.length + idx;
                                const sphere = spheres[sphereIdx];
                                if (!sphere) return;
                                
                                const lineGeometry = new THREE.BufferGeometry();
                                const positions = new Float32Array([
                                    0, 0, 0, // Center (MEMORY.md)
                                    sphere.position.x, sphere.position.y, sphere.position.z
                                ]);
                                lineGeometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
                                
                                const lineOpacity = Math.min(similarity * 0.6, 0.4);
                                const lineMaterial = new THREE.LineBasicMaterial({
                                    color: similarity > 0.5 ? 0xffd700 : 0x88aaff,
                                    transparent: true,
                                    opacity: lineOpacity
                                });
                                
                                const line = new THREE.Line(lineGeometry, lineMaterial);
                                line.userData = { similarity: similarity, radial: true };
                                line.visible = showConnections;
                                scene.add(line);
                                connectionLines.push(line);
                            }
                        });
                    }
                }
                
                // Create initial connections
                createConnectionLines();
                
                // Update hub info with actual similarity stats
                const similarities = otherPoints.map(p => p.similarityToMemory || 0);
                const avgSimilarity = similarities.length > 0 
                    ? similarities.reduce((a, b) => a + b, 0) / similarities.length 
                    : 0;
                const highSimilarity = otherPoints.filter(p => (p.similarityToMemory || 0) > 0.6).length;
                const medSimilarity = otherPoints.filter(p => {
                    const sim = p.similarityToMemory || 0;
                    return sim > 0.4 && sim <= 0.6;
                }).length;
                const lowSimilarity = otherPoints.filter(p => (p.similarityToMemory || 0) <= 0.4).length;
                
                document.getElementById('hub-stats').innerHTML = `
                    Memory points: ${otherPoints.length}<br>
                    MEMORY.md chunks: ${memoryMdPoints.length} (consolidated)<br>
                    High similarity (>60%): ${highSimilarity}<br>
                    Medium (40-60%): ${medSimilarity}<br>
                    Low (<40%): ${lowSimilarity}<br>
                    Avg similarity: ${(avgSimilarity * 100).toFixed(1)}%
                `;
                console.log('Hub stats updated - memory points:', otherPoints.length, 
                    ', MEMORY.md chunks:', memoryMdPoints.length,
                    ', avg similarity:', (avgSimilarity * 100).toFixed(1) + '%');
                
                // Raycaster
                const raycaster = new THREE.Raycaster();
                const mouse = new THREE.Vector2();
                const tooltip = document.getElementById('tooltip');
                
                let selectedSphere = null;
                let hoveredSphere = null;
                
                function onMouseMove(event) {
                    mouse.x = (event.clientX / window.innerWidth) * 2 - 1;
                    mouse.y = -(event.clientY / window.innerHeight) * 2 + 1;
                    
                    raycaster.setFromCamera(mouse, camera);
                    const intersects = raycaster.intersectObjects(spheres);
                    
                    if (intersects.length > 0) {
                        const sphere = intersects[0].object;
                        
                        if (hoveredSphere !== sphere) {
                            if (hoveredSphere && hoveredSphere !== selectedSphere) {
                                resetSphereAppearance(hoveredSphere);
                            }
                            
                            hoveredSphere = sphere;
                            if (sphere !== selectedSphere) {
                                sphere.scale.setScalar(1.5);
                            }
                            
                            const data = sphere.userData.point;
                            const filename = data.path.split('/').pop();
                            const chunkCount = sphere.userData.chunkCount || 1;
                            
                            tooltip.querySelector('.filename').textContent = 
                                sphere.userData.isMemoryMd ? '🧠 ' + filename : filename;
                            tooltip.querySelector('.tier').textContent = sphere.userData.isMemoryMd 
                                ? `${data.tier.toUpperCase()} • ${chunkCount} chunks consolidated`
                                : `${data.tier.toUpperCase()} • ${data.tokens} ${data.tokens === 1 ? 'token' : 'tokens'} • Chunk ${data.chunkIndex + 1}`;
                            
                            const similarity = data.similarityToMemory || 0;
                            tooltip.querySelector('.similarity').textContent = 
                                sphere.userData.isMemoryMd ? 'Central Hub (position: 0,0,0)' : `Similarity: ${(similarity * 100).toFixed(1)}%`;
                            
                            tooltip.classList.add('visible');
                            tooltip.style.left = event.clientX + 15 + 'px';
                            tooltip.style.top = event.clientY + 15 + 'px';
                        }
                        
                        document.body.style.cursor = 'pointer';
                    } else {
                        if (hoveredSphere && hoveredSphere !== selectedSphere) {
                            resetSphereAppearance(hoveredSphere);
                        }
                        hoveredSphere = null;
                        tooltip.classList.remove('visible');
                        document.body.style.cursor = 'default';
                    }
                }
                
                function onClick(event) {
                    raycaster.setFromCamera(mouse, camera);
                    const intersects = raycaster.intersectObjects(spheres);
                    
                    if (intersects.length > 0) {
                        const sphere = intersects[0].object;
                        selectSphere(sphere);
                        window.webkit.messageHandlers.pointSelected.postMessage(sphere.userData.id);
                    }
                }
                
                function selectSphere(sphere) {
                    if (selectedSphere) {
                        resetSphereAppearance(selectedSphere);
                    }
                    
                    selectedSphere = sphere;
                    sphere.scale.setScalar(sphere.userData.isMemoryMd ? 1.3 : 2);
                    sphere.material.emissiveIntensity = 0.8;
                    
                    if (sphere.userData.ring) {
                        scene.remove(sphere.userData.ring);
                    }
                    
                    const ringGeometry = new THREE.RingGeometry(
                        sphere.userData.originalSize * 2.5,
                        sphere.userData.originalSize * 3,
                        32
                    );
                    const ringMaterial = new THREE.MeshBasicMaterial({ 
                        color: 0xffffff, 
                        side: THREE.DoubleSide,
                        transparent: true,
                        opacity: 0.8
                    });
                    const ring = new THREE.Mesh(ringGeometry, ringMaterial);
                    ring.position.copy(sphere.position);
                    ring.lookAt(camera.position);
                    scene.add(ring);
                    sphere.userData.ring = ring;
                }
                
                function resetSphereAppearance(sphere) {
                    sphere.scale.setScalar(1);
                    const point = sphere.userData.point;
                    const similarity = point.similarityToMemory || 0;
                    sphere.material.emissiveIntensity = sphere.userData.isMemoryMd ? 0.6 : (0.2 + similarity * 0.3);
                    
                    if (sphere.userData.ring) {
                        scene.remove(sphere.userData.ring);
                        sphere.userData.ring = null;
                    }
                }
                
                function selectPoint(pointId) {
                    const sphere = pointData.get(pointId);
                    if (sphere) selectSphere(sphere);
                }
                
                function highlightSearch(query) {
                    const lowerQuery = query.toLowerCase();
                    
                    spheres.forEach(sphere => {
                        const data = sphere.userData.point;
                        
                        if (query && lowerQuery.length > 0) {
                            const matches = 
                                data.path.toLowerCase().includes(lowerQuery) ||
                                data.text.toLowerCase().includes(lowerQuery);
                            
                            sphere.material.opacity = matches ? 1 : 0.15;
                            sphere.material.transparent = !matches;
                        } else {
                            sphere.material.opacity = 1;
                            sphere.material.transparent = false;
                        }
                    });
                }
                
                // Auto-fit camera to show all points
                function fitCameraToAllPoints() {
                    if (spheres.length === 0) return;
                    
                    // Calculate bounding box of all points
                    const box = new THREE.Box3();
                    spheres.forEach(sphere => {
                        box.expandByPoint(sphere.position);
                    });
                    
                    const center = box.getCenter(new THREE.Vector3());
                    const size = box.getSize(new THREE.Vector3());
                    const maxDim = Math.max(size.x, size.y, size.z);
                    
                    // Calculate distance to fit all points in view
                    const fov = camera.fov * (Math.PI / 180);
                    const distance = (maxDim / 2) / Math.tan(fov / 2) * 1.8; // 1.8x margin
                    
                    // Position camera to show all points
                    camera.position.set(
                        center.x + distance * 0.7,
                        center.y + distance * 0.5,
                        center.z + distance * 0.7
                    );
                    controls.target.copy(center);
                    controls.update();
                }
                
                function resetCamera() {
                    fitCameraToAllPoints();
                }
                
                function toggleRotation() {
                    controls.autoRotate = !controls.autoRotate;
                }
                
                function toggleConnections() {
                    showConnections = !showConnections;
                    console.log('Toggle connections:', showConnections, 'Lines:', connectionLines.length);
                    connectionLines.forEach(line => {
                        line.visible = showConnections;
                    });
                    const btn = document.getElementById('btn-connections');
                    btn.classList.toggle('active', showConnections);
                    btn.style.background = showConnections ? 'rgba(255, 215, 0, 0.3)' : 'rgba(255, 255, 255, 0.1)';
                }
                
                function focusMemoryMd() {
                    if (memoryMdSphere) {
                        camera.position.set(0.5, 0.3, 0.5);
                        controls.target.set(0, 0, 0);
                        controls.update();
                    }
                }
                
                // Spread control functions
                function easeInOutCubic(t) {
                    return t < 0.5 
                        ? 4 * t * t * t 
                        : 1 - Math.pow(-2 * t + 2, 3) / 2;
                }
                
                function animatePointPosition(mesh, targetPos, duration) {
                    const startPos = mesh.position.clone();
                    const startTime = Date.now();
                    
                    function animate() {
                        const elapsed = Date.now() - startTime;
                        const progress = Math.min(elapsed / duration, 1);
                        const eased = easeInOutCubic(progress);
                        
                        mesh.position.lerpVectors(
                            startPos, 
                            new THREE.Vector3(targetPos.x, targetPos.y, targetPos.z), 
                            eased
                        );
                        
                        if (progress < 1) {
                            requestAnimationFrame(animate);
                        }
                    }
                    
                    animate();
                }
                
                function updateSpread(multiplier) {
                    currentSpreadMultiplier = multiplier;
                    
                    // Update all spheres with animation
                    spheres.forEach(sphere => {
                        const userData = sphere.userData;
                        const point = userData.point;
                        
                        // Skip MEMORY.md - it stays at center
                        if (isMemoryMdPoint(point)) return;
                        
                        // Calculate new position based on original position scaled by multiplier
                        const originalX = point.x;
                        const originalY = point.y;
                        const originalZ = point.z;
                        
                        const newPosition = {
                            x: originalX * multiplier,
                            y: originalY * multiplier,
                            z: originalZ * multiplier
                        };
                        
                        // Animate to new position
                        animatePointPosition(sphere, newPosition, 400);
                        
                        // Store scaled position for ring updates
                        userData.scaledPosition = newPosition;
                    });
                    
                    // Update connection lines after a short delay
                    setTimeout(() => {
                        updateConnectionLines();
                    }, 420);
                    
                    // Save to localStorage
                    try {
                        localStorage.setItem('memorySpreadMultiplier', multiplier.toString());
                    } catch (e) {
                        console.log('Could not save spread to localStorage');
                    }
                }
                
                function updateConnectionLines() {
                    // Recreate connection lines with current positions
                    createConnectionLines();
                }
                
                function restoreSavedSpread() {
                    try {
                        const saved = localStorage.getItem('memorySpreadMultiplier');
                        if (saved) {
                            const multiplier = parseFloat(saved);
                            if (!isNaN(multiplier) && multiplier >= 0.1 && multiplier <= 3.0) {
                                currentSpreadMultiplier = multiplier;
                                // Apply spread without animation on initial load
                                spheres.forEach(sphere => {
                                    const point = sphere.userData.point;
                                    if (isMemoryMdPoint(point)) return;
                                    
                                    sphere.position.set(
                                        point.x * multiplier,
                                        point.y * multiplier,
                                        point.z * multiplier
                                    );
                                });
                                updateConnectionLines();
                                
                                // Notify Swift of restored spread
                                window.webkit.messageHandlers.spreadChanged.postMessage(multiplier);
                            }
                        }
                    } catch (e) {
                        console.log('Could not restore spread from localStorage');
                    }
                }
                
                // Keyboard shortcuts for spread
                function handleKeyDown(event) {
                    // [ key - decrease spread by 10%
                    if (event.key === '[') {
                        const newSpread = Math.max(0.1, currentSpreadMultiplier - 0.1);
                        updateSpread(newSpread);
                        window.webkit.messageHandlers.spreadChanged.postMessage(newSpread);
                    }
                    // ] key - increase spread by 10%
                    else if (event.key === ']') {
                        const newSpread = Math.min(3.0, currentSpreadMultiplier + 0.1);
                        updateSpread(newSpread);
                        window.webkit.messageHandlers.spreadChanged.postMessage(newSpread);
                    }
                    // 0 key - reset spread to 100%
                    else if (event.key === '0') {
                        updateSpread(1.0);
                        window.webkit.messageHandlers.spreadChanged.postMessage(1.0);
                    }
                }
                
                // Event listeners
                window.addEventListener('mousemove', onMouseMove);
                window.addEventListener('click', onClick);
                window.addEventListener('keydown', handleKeyDown);
                
                window.addEventListener('resize', () => {
                    camera.aspect = window.innerWidth / window.innerHeight;
                    camera.updateProjectionMatrix();
                    renderer.setSize(window.innerWidth, window.innerHeight);
                });
                
                // Animation loop
                let time = 0;
                function animate() {
                    requestAnimationFrame(animate);
                    time += 0.01;
                    
                    controls.update();
                    
                    // Pulse MEMORY.md glow
                    if (memoryMdSphere && memoryMdSphere.userData.outerGlow) {
                        const pulse = 0.03 + Math.sin(time * 2) * 0.02;
                        memoryMdSphere.userData.outerGlow.material.opacity = pulse;
                    }
                    
                    // Update selection rings
                    spheres.forEach(sphere => {
                        if (sphere.userData.ring) {
                            sphere.userData.ring.lookAt(camera.position);
                        }
                    });
                    
                    renderer.render(scene, camera);
                }
                
                // Initialize
                const connectionsBtn = document.getElementById('btn-connections');
                connectionsBtn.classList.add('active');
                connectionsBtn.style.background = 'rgba(255, 215, 0, 0.3)';
                console.log('Connections initialized:', showConnections, 'Lines:', connectionLines.length);
                
                // Restore saved spread from localStorage
                restoreSavedSpread();
                
                // Auto-fit camera to show all points on load
                fitCameraToAllPoints();
                
                animate();
                
                // Expose functions globally for HTML onclick handlers
                window.resetCamera = resetCamera;
                window.toggleRotation = toggleRotation;
                window.toggleConnections = toggleConnections;
                window.focusMemoryMd = focusMemoryMd;
                window.updateSpread = updateSpread;
                window.selectPoint = selectPoint;
                window.highlightSearch = highlightSearch;
                
                window.webkit.messageHandlers.vizReady.postMessage(true);
                } // End of initVisualization()
            </script>
        </body>
        </html>
        """
    }
}
