//
//  ChartData.swift
//  ClawK
//
//  Data models and transformation logic for custom Canvas-based chart
//

import Foundation
import CoreGraphics

// MARK: - Chart Data Models

/// A single data point for chart rendering
/// Represents per-heartbeat activity (delta, not cumulative)
struct ChartPoint: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let value: Int      // Items logged in this heartbeat (delta)
    let status: String  // "HEARTBEAT_OK" or "HEARTBEAT_ALERT"
    
    static func == (lhs: ChartPoint, rhs: ChartPoint) -> Bool {
        lhs.timestamp == rhs.timestamp && lhs.value == rhs.value && lhs.status == rhs.status
    }
}

/// Chart layout dimensions and margins
struct ChartDimensions {
    let width: CGFloat
    let height: CGFloat
    
    // Margins (in pixels)
    let marginTop: CGFloat = 8
    let marginRight: CGFloat = 8
    let marginBottom: CGFloat = 20    // Space for X-axis labels
    let marginLeft: CGFloat = 28      // Space for Y-axis labels (hidden but reserved)
    
    /// Width of the actual plot area
    var plotWidth: CGFloat {
        max(0, width - marginLeft - marginRight)
    }
    
    /// Height of the actual plot area
    var plotHeight: CGFloat {
        max(0, height - marginTop - marginBottom)
    }
    
    /// The rectangle defining the plot area
    var plotRect: CGRect {
        CGRect(
            x: marginLeft,
            y: marginTop,
            width: plotWidth,
            height: plotHeight
        )
    }
}

/// Scale for converting data values to pixel positions
struct ChartScale {
    let xMin: Date
    let xMax: Date
    let yMin: Int
    let yMax: Int
    
    init(xMin: Date, xMax: Date, yMin: Int = 0, yMax: Int) {
        self.xMin = xMin
        self.xMax = xMax
        self.yMin = yMin
        self.yMax = max(yMax, yMin + 1) // Prevent division by zero
    }
    
    /// Convert a date to X pixel position within the plot area
    /// Formula: (date - xMin) / (xMax - xMin) * plotWidth + marginLeft
    func xPosition(for date: Date, in dimensions: ChartDimensions) -> CGFloat {
        let xRange = xMax.timeIntervalSince(xMin)
        
        // Handle edge case: xMin == xMax (single point or no range)
        guard xRange > 0 else {
            return dimensions.marginLeft + dimensions.plotWidth / 2
        }
        
        let normalizedX = date.timeIntervalSince(xMin) / xRange
        return dimensions.marginLeft + CGFloat(normalizedX) * dimensions.plotWidth
    }
    
    /// Convert a value to Y pixel position within the plot area
    /// Note: Canvas Y is inverted (0,0 is top-left, but chart 0 is at bottom)
    /// Formula: plotHeight - ((value - yMin) / (yMax - yMin) * plotHeight) + marginTop
    func yPosition(for value: Int, in dimensions: ChartDimensions) -> CGFloat {
        let yRange = yMax - yMin
        
        // Handle edge case: yMin == yMax (flat line)
        guard yRange > 0 else {
            return dimensions.marginTop + dimensions.plotHeight / 2
        }
        
        let normalizedY = Double(value - yMin) / Double(yRange)
        // Invert Y: higher values should be at the top (lower pixel Y)
        return dimensions.marginTop + CGFloat(1.0 - normalizedY) * dimensions.plotHeight
    }
    
    /// Get the CGPoint for a chart point
    func position(for point: ChartPoint, in dimensions: ChartDimensions) -> CGPoint {
        CGPoint(
            x: xPosition(for: point.timestamp, in: dimensions),
            y: yPosition(for: point.value, in: dimensions)
        )
    }
}

// MARK: - Data Transformation

/// Transform HeartbeatHistory array to ChartPoint array
/// Applies delta calculation: each point shows items logged in THAT heartbeat, not running total
func transformToChartPoints(from history: [HeartbeatHistory]) -> [ChartPoint] {
    // Filter to last 24 hours and sort by timestamp
    let cutoff = Date().addingTimeInterval(-24 * 3600)
    let sorted = history
        .filter { $0.timestamp > cutoff }
        .sorted { $0.timestamp < $1.timestamp }
    
    guard !sorted.isEmpty else { return [] }
    
    var result: [ChartPoint] = []
    
    for i in 0..<sorted.count {
        let current = sorted[i].memoryEventsLogged
        let previous = i > 0 ? sorted[i-1].memoryEventsLogged : 0
        let delta = max(0, current - previous)  // Prevent negatives
        
        result.append(ChartPoint(
            timestamp: sorted[i].timestamp,
            value: delta,
            status: sorted[i].status
        ))
    }
    
    return result
}

// MARK: - Scale Calculation

/// Calculate the Y-axis maximum from data points
/// Returns a "nice" rounded number for clean axis labels
func calculateYMax(from points: [ChartPoint]) -> Int {
    let maxValue = points.map(\.value).max() ?? 0
    return roundUpToNiceNumber(max(maxValue, 1))  // At least 1 to avoid empty scale
}

/// Round a value up to a "nice" number for axis labels
/// Examples: 7→10, 12→15, 23→25, 35→50, 75→100
func roundUpToNiceNumber(_ value: Int) -> Int {
    guard value > 0 else { return 10 }
    
    // Nice number intervals: 5, 10, 20, 25, 50, 100, etc.
    let niceIntervals = [5, 10, 15, 20, 25, 50, 100, 200, 250, 500, 1000]
    
    for interval in niceIntervals {
        let rounded = ((value + interval - 1) / interval) * interval
        if rounded >= value {
            return rounded
        }
    }
    
    // For very large values, round to nearest power of 10
    let magnitude = Int(pow(10, floor(log10(Double(value)))))
    return ((value + magnitude - 1) / magnitude) * magnitude
}

/// Calculate time range for the chart
/// Default: last 24 hours ending at current time
func calculateTimeRange(from points: [ChartPoint]) -> (min: Date, max: Date) {
    let now = Date()
    let defaultStart = now.addingTimeInterval(-24 * 3600)
    
    guard !points.isEmpty else {
        return (defaultStart, now)
    }
    
    // Use data range or default 24h range, whichever is appropriate
    let dataMin = points.map(\.timestamp).min() ?? defaultStart
    let dataMax = points.map(\.timestamp).max() ?? now
    
    // Always show at least 24 hours for context
    return (min(dataMin, defaultStart), max(dataMax, now))
}

/// Create a ChartScale from chart points
func createScale(from points: [ChartPoint], yMax: Int? = nil) -> ChartScale {
    let timeRange = calculateTimeRange(from: points)
    let calculatedYMax = yMax ?? calculateYMax(from: points)
    
    return ChartScale(
        xMin: timeRange.min,
        xMax: timeRange.max,
        yMin: 0,
        yMax: max(calculatedYMax, 10)  // Minimum yMax of 10
    )
}

// MARK: - Axis Tick Generation

/// X-axis tick information
struct XAxisTick {
    let date: Date
    let label: String
    let position: CGFloat
}

/// Y-axis tick information
struct YAxisTick {
    let value: Int
    let label: String
    let position: CGFloat
}

/// Generate X-axis ticks at regular time intervals
/// Default: every 6 hours for a 24-hour chart
func generateXAxisTicks(scale: ChartScale, dimensions: ChartDimensions, hoursInterval: Int = 6) -> [XAxisTick] {
    var ticks: [XAxisTick] = []
    
    let calendar = Calendar.current
    
    // Find the first "round" hour on or after xMin
    let startHour = calendar.component(.hour, from: scale.xMin)
    let roundedStartHour = ((startHour + hoursInterval - 1) / hoursInterval) * hoursInterval
    
    // Get the start of the day for xMin
    guard let startOfDay = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: scale.xMin),
          var currentTick = calendar.date(byAdding: .hour, value: roundedStartHour, to: startOfDay) else {
        return []
    }
    
    // If the first tick is before xMin, move to next interval
    if currentTick < scale.xMin {
        currentTick = calendar.date(byAdding: .hour, value: hoursInterval, to: currentTick) ?? currentTick
    }
    
    // Generate ticks until we pass xMax
    while currentTick <= scale.xMax {
        let position = scale.xPosition(for: currentTick, in: dimensions)
        let label = formatTimeLabel(currentTick)
        
        ticks.append(XAxisTick(
            date: currentTick,
            label: label,
            position: position
        ))
        
        guard let nextTick = calendar.date(byAdding: .hour, value: hoursInterval, to: currentTick) else {
            break
        }
        currentTick = nextTick
    }
    
    return ticks
}

/// Generate Y-axis ticks based on scale
/// Returns 3 ticks: 0, mid, max
func generateYAxisTicks(scale: ChartScale, dimensions: ChartDimensions) -> [YAxisTick] {
    let yMax = scale.yMax
    let yMin = scale.yMin
    
    // Determine nice tick values
    let tickValues: [Int]
    if yMax <= 10 {
        tickValues = [0, 5, 10]
    } else if yMax <= 20 {
        tickValues = [0, 10, 20]
    } else if yMax <= 50 {
        tickValues = [0, 25, 50]
    } else if yMax <= 100 {
        tickValues = [0, 50, 100]
    } else {
        tickValues = [yMin, (yMin + yMax) / 2, yMax]
    }
    
    return tickValues.map { value in
        YAxisTick(
            value: value,
            label: "\(value)",
            position: scale.yPosition(for: value, in: dimensions)
        )
    }
}

// MARK: - Formatting Helpers

/// Format a date for X-axis display
/// Output: "12 AM", "6 AM", "12 PM", "6 PM"
func formatTimeLabel(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "h a"  // "4 AM", "10 AM", "4 PM"
    return formatter.string(from: date)
}

/// Format a date with more detail for tooltips
func formatTimeLabelDetailed(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"  // "4:30 AM", "10:15 AM"
    return formatter.string(from: date)
}

// MARK: - Point Color Helpers

/// Determine the color for a data point based on activity level and status
/// Returns a tuple of (red, green, blue, alpha) for use in Canvas
func pointColorComponents(for point: ChartPoint) -> (red: Double, green: Double, blue: Double, alpha: Double) {
    // Alert status = red
    if point.status != "HEARTBEAT_OK" {
        return (0.86, 0.16, 0.16, 1.0)  // .red equivalent
    }
    
    // Color based on activity level (per-heartbeat delta)
    if point.value >= 15 {
        // High activity = purple
        return (0.5, 0.0, 0.5, 1.0)
    } else if point.value >= 8 {
        // Medium activity = blue
        return (0.0, 0.478, 1.0, 1.0)
    } else {
        // Low activity = indigo (with slight transparency)
        return (0.294, 0.0, 0.51, 0.8)
    }
}

// MARK: - Edge Case Handling

/// Check if chart data is empty
func isChartEmpty(_ points: [ChartPoint]) -> Bool {
    points.isEmpty
}

/// Check if chart is in "collecting" state (not enough data for a line)
func isCollectingState(_ points: [ChartPoint]) -> Bool {
    points.count > 0 && points.count < 3
}

/// Check if all values are the same (flat line)
func isFlatLine(_ points: [ChartPoint]) -> Bool {
    guard points.count > 1 else { return false }
    let firstValue = points[0].value
    return points.allSatisfy { $0.value == firstValue }
}

/// Check if this is a single data point
func isSinglePoint(_ points: [ChartPoint]) -> Bool {
    points.count == 1
}

// MARK: - Pre-calculated Chart Data Bundle

/// A bundle of pre-calculated chart data for efficient rendering
struct ChartDataBundle {
    let points: [ChartPoint]
    let scale: ChartScale
    let isEmpty: Bool
    let isCollecting: Bool
    let isFlatLine: Bool
    let isSinglePoint: Bool
    
    /// Create from raw HeartbeatHistory data
    static func create(from history: [HeartbeatHistory]) -> ChartDataBundle {
        let points = transformToChartPoints(from: history)
        let scale = createScale(from: points)
        
        return ChartDataBundle(
            points: points,
            scale: scale,
            isEmpty: isChartEmpty(points),
            isCollecting: isCollectingState(points),
            isFlatLine: ClawK.isFlatLine(points),
            isSinglePoint: ClawK.isSinglePoint(points)
        )
    }
    
    /// Get scaled positions for all points
    func scaledPositions(in dimensions: ChartDimensions) -> [CGPoint] {
        points.map { scale.position(for: $0, in: dimensions) }
    }
    
    /// Get X-axis ticks
    func xAxisTicks(in dimensions: ChartDimensions) -> [XAxisTick] {
        generateXAxisTicks(scale: scale, dimensions: dimensions)
    }
    
    /// Get Y-axis ticks
    func yAxisTicks(in dimensions: ChartDimensions) -> [YAxisTick] {
        generateYAxisTicks(scale: scale, dimensions: dimensions)
    }
}
