//
//  CustomHeartbeatChart.swift
//  ClawK
//
//  Custom Canvas-based heartbeat chart replacing Swift Charts
//  Provides full control over rendering for production quality
//

import SwiftUI

struct CustomHeartbeatChart: View {
    let history: [HeartbeatHistory]
    
    // MARK: - Empty State Enum
    
    /// States for empty/collecting display
    private enum EmptyState {
        case noData
        case collecting(count: Int)
        
        var icon: String {
            switch self {
            case .noData: return "waveform.path.ecg"
            case .collecting: return "arrow.triangle.2.circlepath"
            }
        }
        
        var message: String {
            switch self {
            case .noData: return "Collecting data..."
            case .collecting(let count): return "Collecting data... (\(count)/3 points)"
            }
        }
        
        var subtitle: String? {
            switch self {
            case .noData: return "Activity will appear after heartbeats run"
            case .collecting: return nil
            }
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        let bundle = ChartDataBundle.create(from: history)
        
        VStack(alignment: .leading, spacing: 0) {
            if bundle.isEmpty {
                emptyStateView(state: .noData)
            } else if bundle.isCollecting {
                collectingStateView(bundle: bundle)
            } else {
                chartView(bundle: bundle)
            }
        }
    }
    
    // MARK: - Empty State View
    
    @ViewBuilder
    private func emptyStateView(state: EmptyState) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: state.icon)
                    .font(.system(size: 28))
                    .foregroundColor(.purple.opacity(0.4))
                
                Text(state.message)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                if let subtitle = state.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            Spacer()
        }
        .frame(height: 100)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.purple.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.purple.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal, 4)
        .padding(.top, 12)
    }
    
    // MARK: - Collecting State View
    
    @ViewBuilder
    private func collectingStateView(bundle: ChartDataBundle) -> some View {
        VStack(spacing: 10) {
            // Mini chart with just data points (no line)
            GeometryReader { geometry in
                Canvas { context, size in
                    let dimensions = ChartDimensions(
                        width: size.width,
                        height: size.height
                    )
                    
                    let scaledPoints = bundle.scaledPositions(in: dimensions)
                    
                    // Draw just the points (no grid, no line for collecting state)
                    drawDataPoints(
                        in: &context,
                        scaledPoints: scaledPoints,
                        points: bundle.points
                    )
                }
            }
            .frame(height: 70)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.purple.opacity(0.02))
            )
            
            // Progress indicator with count
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Collecting data... (\(bundle.points.count)/3 points)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .padding(.top, 12)
    }
    
    // MARK: - Main Chart View
    
    @ViewBuilder
    private func chartView(bundle: ChartDataBundle) -> some View {
        GeometryReader { geometry in
            Canvas { context, size in
                // Create dimensions for the chart layout
                let dimensions = ChartDimensions(
                    width: size.width,
                    height: size.height
                )
                
                // Get pre-calculated tick positions
                let xTicks = bundle.xAxisTicks(in: dimensions)
                let yTicks = bundle.yAxisTicks(in: dimensions)
                
                // Get scaled point positions
                let scaledPoints = bundle.scaledPositions(in: dimensions)
                
                // Handle narrow width: filter X-axis labels if too cramped
                let filteredXTicks = filterXTicksForWidth(xTicks, width: size.width)
                
                // Draw in layers (back to front):
                
                // 1. Grid lines (background layer)
                drawGrid(
                    in: &context,
                    dimensions: dimensions,
                    xTicks: xTicks,  // Keep all grid lines
                    yTicks: yTicks
                )
                
                // 2. X-axis labels (below chart) - filtered for narrow widths
                drawXAxisLabels(
                    in: &context,
                    dimensions: dimensions,
                    xTicks: filteredXTicks
                )
                
                // 3. Y-axis labels (left side) - showing token counts in thousands
                drawYAxisLabels(
                    in: &context,
                    dimensions: dimensions,
                    yTicks: yTicks
                )
                
                // 3. Area fill (behind line)
                drawAreaFill(
                    in: &context,
                    dimensions: dimensions,
                    scaledPoints: scaledPoints
                )
                
                // 4. Line (on top of area)
                drawLine(
                    in: &context,
                    scaledPoints: scaledPoints
                )
                
                // 5. Data points (on top of everything)
                drawDataPoints(
                    in: &context,
                    scaledPoints: scaledPoints,
                    points: bundle.points
                )
            }
        }
        .frame(height: 120)  // Fixed height per design spec
        .padding(.horizontal, 4)
        .padding(.top, 12)
    }
    
    // MARK: - Narrow Width Handling
    
    /// Filter X-axis ticks for narrow widths to prevent label overlap
    /// At width < 200px: show every other label
    /// At width < 150px: show every third label
    private func filterXTicksForWidth(_ ticks: [XAxisTick], width: CGFloat) -> [XAxisTick] {
        guard !ticks.isEmpty else { return ticks }
        
        let skipFactor: Int
        if width < 150 {
            skipFactor = 3  // Show every 3rd label
        } else if width < 200 {
            skipFactor = 2  // Show every 2nd label
        } else {
            skipFactor = 1  // Show all labels
        }
        
        return ticks.enumerated()
            .filter { $0.offset % skipFactor == 0 }
            .map(\.element)
    }
    
    // MARK: - Grid Rendering
    
    /// Draw vertical and horizontal grid lines
    /// Grid lines are rendered first (background layer)
    private func drawGrid(
        in context: inout GraphicsContext,
        dimensions: ChartDimensions,
        xTicks: [XAxisTick],
        yTicks: [YAxisTick]
    ) {
        // Grid line styling per design spec
        let gridColor = Color.gray.opacity(0.3)
        let dashPattern: [CGFloat] = [2, 2]
        let strokeStyle = StrokeStyle(lineWidth: 0.5, dash: dashPattern)
        
        // Plot area boundaries
        let plotTop = dimensions.marginTop
        let plotBottom = dimensions.height - dimensions.marginBottom
        let plotLeft = dimensions.marginLeft
        let plotRight = dimensions.width - dimensions.marginRight
        
        // Draw vertical grid lines at each X-axis tick (time intervals)
        for tick in xTicks {
            var path = Path()
            path.move(to: CGPoint(x: tick.position, y: plotTop))
            path.addLine(to: CGPoint(x: tick.position, y: plotBottom))
            
            context.stroke(
                path,
                with: .color(gridColor),
                style: strokeStyle
            )
        }
        
        // Draw horizontal grid lines at each Y-axis tick (value intervals)
        for tick in yTicks {
            var path = Path()
            path.move(to: CGPoint(x: plotLeft, y: tick.position))
            path.addLine(to: CGPoint(x: plotRight, y: tick.position))
            
            context.stroke(
                path,
                with: .color(gridColor),
                style: strokeStyle
            )
        }
    }
    
    // MARK: - X-Axis Labels
    
    /// Draw X-axis time labels below the chart
    /// Labels are centered on their corresponding tick positions
    private func drawXAxisLabels(
        in context: inout GraphicsContext,
        dimensions: ChartDimensions,
        xTicks: [XAxisTick]
    ) {
        // Label styling per design spec
        // Font: .caption2 (matches existing HeartbeatGraph axis labels)
        // Color: .secondary (adapts to light/dark mode)
        
        // Y position: 4px below the plot area bottom edge
        let labelY = dimensions.height - dimensions.marginBottom + 4
        
        for tick in xTicks {
            // Create styled text for the label
            let text = Text(tick.label)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            // Draw label centered horizontally on the tick position
            // anchor: .top centers horizontally and aligns top edge to position
            context.draw(
                text,
                at: CGPoint(x: tick.position, y: labelY),
                anchor: .top
            )
        }
    }
    
    // MARK: - Y-Axis Labels
    
    /// Draw Y-axis value labels on the left side of the chart
    /// Shows memory event counts (formatted as integers for small values)
    private func drawYAxisLabels(
        in context: inout GraphicsContext,
        dimensions: ChartDimensions,
        yTicks: [YAxisTick]
    ) {
        // Label styling: matches X-axis (.caption2, gray)
        // X position: 4px from left margin (right-aligned to leave space for chart)
        let labelX = dimensions.marginLeft - 4
        
        for tick in yTicks {
            // Format the value (memory events are typically small numbers)
            let label = "\(tick.value)"
            
            // Create styled text for the label
            let text = Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            // Draw label right-aligned to the left of the plot area
            // anchor: .trailing aligns the right edge of text to the position
            context.draw(
                text,
                at: CGPoint(x: labelX, y: tick.position),
                anchor: .trailing
            )
        }
    }
    
    // MARK: - Area Fill
    
    /// Draw gradient-filled area under the line
    /// Creates a closed path from line down to X-axis baseline
    private func drawAreaFill(
        in context: inout GraphicsContext,
        dimensions: ChartDimensions,
        scaledPoints: [CGPoint]
    ) {
        // Skip if no points to draw
        guard !scaledPoints.isEmpty else { return }
        
        var path = Path()
        
        // Start at bottom-left of first point (on X-axis baseline)
        let firstPoint = scaledPoints[0]
        let baseline = dimensions.height - dimensions.marginBottom
        
        path.move(to: CGPoint(x: firstPoint.x, y: baseline))
        
        // Draw line up to first point
        path.addLine(to: CGPoint(x: firstPoint.x, y: firstPoint.y))
        
        // Connect all points
        for point in scaledPoints.dropFirst() {
            path.addLine(to: CGPoint(x: point.x, y: point.y))
        }
        
        // Draw down to bottom at last point
        if let lastPoint = scaledPoints.last {
            path.addLine(to: CGPoint(x: lastPoint.x, y: baseline))
        }
        
        // Close path back to start
        path.closeSubpath()
        
        // Fill with vertical gradient (purple fading down)
        // Per design spec: 30% opacity at top → 5% opacity at bottom
        let gradient = Gradient(colors: [
            Color.purple.opacity(0.3),
            Color.purple.opacity(0.05)
        ])
        
        context.fill(
            path,
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: 0, y: dimensions.marginTop),
                endPoint: CGPoint(x: 0, y: baseline)
            )
        )
    }
    
    // MARK: - Line
    
    /// Draw connecting line between all data points
    /// Uses purple color with rounded line style
    private func drawLine(
        in context: inout GraphicsContext,
        scaledPoints: [CGPoint]
    ) {
        // Need at least 2 points to draw a line
        guard scaledPoints.count > 1 else { return }
        
        var path = Path()
        path.move(to: scaledPoints[0])
        
        for point in scaledPoints.dropFirst() {
            path.addLine(to: point)
        }
        
        // Stroke with purple color per design spec
        // Width: 2px, round caps and joins for smooth appearance
        context.stroke(
            path,
            with: .color(Color.purple),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )
    }
    
    // MARK: - Data Points
    
    /// Draw circles at each data point with color based on activity level
    /// Colors: Purple (>=15), Blue (8-14), Indigo (<8), Red (alert status)
    private func drawDataPoints(
        in context: inout GraphicsContext,
        scaledPoints: [CGPoint],
        points: [ChartPoint]
    ) {
        // Ensure we have matching points and positions
        guard scaledPoints.count == points.count else { return }
        
        // Point dimensions per design spec
        let radius: CGFloat = 3  // 6px diameter = 3px radius
        
        for (index, scaledPoint) in scaledPoints.enumerated() {
            let point = points[index]
            
            // Determine fill color based on value threshold and status
            let color: Color
            if point.status != "HEARTBEAT_OK" {
                color = .red  // Alert status
            } else if point.value >= 15 {
                color = .purple  // High activity
            } else if point.value >= 8 {
                color = .blue  // Medium activity
            } else {
                color = .indigo.opacity(0.8)  // Low activity
            }
            
            // Create circle path
            let circleRect = CGRect(
                x: scaledPoint.x - radius,
                y: scaledPoint.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            let circlePath = Path(ellipseIn: circleRect)
            
            // Draw filled circle
            context.fill(circlePath, with: .color(color))
            
            // Draw white stroke for visibility (1px per design spec)
            context.stroke(
                circlePath,
                with: .color(.white),
                style: StrokeStyle(lineWidth: 1)
            )
        }
    }
}

// MARK: - Preview Provider

#if DEBUG
struct CustomHeartbeatChart_Previews: PreviewProvider {
    static var sampleHistory: [HeartbeatHistory] {
        // Simulate a typical day with accumulating entries
        (0..<20).map { i -> HeartbeatHistory in
            let hoursAgo = 20 - i
            return HeartbeatHistory(
                timestamp: Date().addingTimeInterval(Double(-hoursAgo) * 3600),
                status: "HEARTBEAT_OK",
                contextPercent: 45.0,
                sessionsChecked: 3,
                sessionsActive: 2,
                memoryEventsLogged: i * 3,  // Cumulative, will be converted to delta
                statusDescription: "Normal operation"
            )
        }
    }
    
    // Flat line data (all same values after delta calculation)
    static var flatLineHistory: [HeartbeatHistory] {
        (0..<10).map { i -> HeartbeatHistory in
            let hoursAgo = 10 - i
            return HeartbeatHistory(
                timestamp: Date().addingTimeInterval(Double(-hoursAgo) * 3600),
                status: "HEARTBEAT_OK",
                contextPercent: 45.0,
                sessionsChecked: 3,
                sessionsActive: 2,
                memoryEventsLogged: i * 5,  // Constant delta of 5
                statusDescription: "Normal operation"
            )
        }
    }
    
    // Very high values
    static var highValueHistory: [HeartbeatHistory] {
        (0..<10).map { i -> HeartbeatHistory in
            let hoursAgo = 10 - i
            return HeartbeatHistory(
                timestamp: Date().addingTimeInterval(Double(-hoursAgo) * 3600),
                status: "HEARTBEAT_OK",
                contextPercent: 45.0,
                sessionsChecked: 3,
                sessionsActive: 2,
                memoryEventsLogged: i * 30,  // High delta of ~30 per heartbeat
                statusDescription: "Normal operation"
            )
        }
    }
    
    // Two points (collecting state)
    static var collectingHistory: [HeartbeatHistory] {
        [
            HeartbeatHistory(
                timestamp: Date().addingTimeInterval(-5 * 3600),
                status: "HEARTBEAT_OK",
                contextPercent: 45.0,
                sessionsChecked: 3,
                sessionsActive: 2,
                memoryEventsLogged: 5,
                statusDescription: "Normal operation"
            ),
            HeartbeatHistory(
                timestamp: Date().addingTimeInterval(-3 * 3600),
                status: "HEARTBEAT_OK",
                contextPercent: 45.0,
                sessionsChecked: 3,
                sessionsActive: 2,
                memoryEventsLogged: 12,
                statusDescription: "Normal operation"
            )
        ]
    }
    
    static var previews: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Normal data
                VStack(alignment: .leading) {
                    Text("Normal Data (20 points)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    CustomHeartbeatChart(history: sampleHistory)
                        .background(Color.gray.opacity(0.1))
                }
                
                // Empty state
                VStack(alignment: .leading) {
                    Text("Empty State")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    CustomHeartbeatChart(history: [])
                        .background(Color.gray.opacity(0.1))
                }
                
                // Collecting state (2 points)
                VStack(alignment: .leading) {
                    Text("Collecting State (2 points)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    CustomHeartbeatChart(history: collectingHistory)
                        .background(Color.gray.opacity(0.1))
                }
                
                // Single point
                VStack(alignment: .leading) {
                    Text("Single Point")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    CustomHeartbeatChart(history: [sampleHistory[0]])
                        .background(Color.gray.opacity(0.1))
                }
                
                // Flat line
                VStack(alignment: .leading) {
                    Text("Flat Line (constant delta)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    CustomHeartbeatChart(history: flatLineHistory)
                        .background(Color.gray.opacity(0.1))
                }
                
                // High values
                VStack(alignment: .leading) {
                    Text("High Values (~30 per heartbeat)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    CustomHeartbeatChart(history: highValueHistory)
                        .background(Color.gray.opacity(0.1))
                }
                
                // Narrow width test
                VStack(alignment: .leading) {
                    Text("Narrow Width (<200px)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    CustomHeartbeatChart(history: sampleHistory)
                        .frame(width: 180)
                        .background(Color.gray.opacity(0.1))
                }
            }
            .padding()
        }
        .frame(width: 400, height: 800)
    }
}
#endif
