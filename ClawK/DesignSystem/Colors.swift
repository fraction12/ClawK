//
//  Colors.swift
//  ClawK
//
//  Centralized color system for consistent UI
//  Part of Design System - Round 2
//

import SwiftUI

// MARK: - Design System Colors

extension Color {
    
    // MARK: - Semantic Colors
    
    struct Semantic {
        // Status
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        static let info = Color.blue
        static let neutral = Color.gray
        
        // Connection
        static let connected = Color.green
        static let disconnected = Color.red
        static let stale = Color.orange
        
        // Background states
        static let successBackground = Color.green.opacity(0.1)
        static let warningBackground = Color.orange.opacity(0.1)
        static let errorBackground = Color.red.opacity(0.1)
        static let infoBackground = Color.blue.opacity(0.1)
    }
    
    // MARK: - Accent Colors
    
    struct Accent {
        // Primary accents for different contexts
        static let telegram = Color.blue
        static let model = Color.purple
        static let cron = Color.blue
        static let subagent = Color.purple
        static let system = Color.teal
        static let chart = Color.purple
        
        // Secondary accents
        static let opus = Color.blue
        static let sonnet = Color.purple
        static let haiku = Color.green
        
        // Special
        static let memoryMd = Color.yellow
        static let quota = Color.indigo
    }
    
    // MARK: - Card Header Colors
    
    struct CardHeader {
        static let activeNow = Color.orange
        static let upcomingCrons = Color.blue
        static let sessionStats = Color.green
        static let subagents = Color.purple
        static let recentActivity = Color.gray
        static let claudeUsage = Color.blue
        static let modelUsage = Color.indigo
        static let systemStatus = Color.teal
        static let connection = Color.teal
        static let refresh = Color.orange
        static let about = Color.gray
        static let fileBrowser = Color.blue
        static let filePreview = Color.green
        static let searchResults = Color.purple
        static let visualization = Color.orange
        static let heartbeat = Color.purple
    }
    
    // MARK: - Progress/Gauge Colors
    
    struct Progress {
        static let low = Color.green        // 0-59%
        static let medium = Color.orange    // 60-79%
        static let high = Color.red         // 80-100%
        
        static func forPercent(_ percent: Double) -> Color {
            if percent >= 80 { return high }
            if percent >= 60 { return medium }
            return low
        }
    }
    
    // MARK: - Pace Status Colors
    
    struct Pace {
        static let safe = Color.green       // Well under budget
        static let onTrack = Color.blue     // Tracking normally
        static let elevated = Color.orange  // Slightly ahead
        static let critical = Color.red     // Over pace
    }
    
    // MARK: - Surface Colors
    
    struct Surface {
        static let primary = Color(nsColor: .windowBackgroundColor)
        static let secondary = Color(nsColor: .controlBackgroundColor)
        static let tertiary = Color(nsColor: .textBackgroundColor)
        static let elevated = Color(nsColor: .controlBackgroundColor)
    }
    
    // MARK: - Text Colors
    
    struct Text {
        static let primary = Color.primary
        static let secondary = Color.secondary
        static let tertiary = Color.secondary.opacity(0.7)
        static let disabled = Color.secondary.opacity(0.5)
    }
    
    // MARK: - Border Colors
    
    struct Border {
        static let subtle = Color.secondary.opacity(0.2)
        static let normal = Color.secondary.opacity(0.3)
        static let strong = Color.secondary.opacity(0.5)
    }
    
    // MARK: - Shadow
    
    struct Shadow {
        static let color = Color.black.opacity(0.05)
    }
}

// MARK: - Opacity Presets

extension Color {
    struct Opacity {
        static let ultraLight: Double = 0.05
        static let light: Double = 0.1
        static let medium: Double = 0.15
        static let normal: Double = 0.2
        static let strong: Double = 0.3
        static let heavy: Double = 0.5
        static let solid: Double = 0.8
    }
    
    /// Returns color with standard light opacity (0.1) for backgrounds
    var backgroundLight: Color { self.opacity(Opacity.light) }
    
    /// Returns color with medium opacity (0.15) for badges/chips
    var backgroundMedium: Color { self.opacity(Opacity.medium) }
    
    /// Returns color with strong opacity (0.3) for emphasis
    var backgroundStrong: Color { self.opacity(Opacity.strong) }
}

// MARK: - Session Type Colors

extension Color {
    static func forSessionType(_ key: String) -> Color {
        if key.contains("telegram") { return Accent.telegram }
        if key == AppConfiguration.shared.mainSessionKey { return Accent.model }
        if key.contains("subagent") { return Accent.subagent }
        return .orange
    }
}

// MARK: - Memory Tier Colors

extension Color {
    struct MemoryTier {
        static let hot = Color.red
        static let warm = Color.orange
        static let cold = Color.blue
        static let archive = Color.gray
        
        static func forTier(_ tier: String) -> Color {
            switch tier.lowercased() {
            case "hot": return hot
            case "warm": return warm
            case "cold": return cold
            case "archive": return archive
            default: return .gray
            }
        }
    }
}

// MARK: - Health Status Colors

extension Color {
    struct Health {
        static let healthy = Color.green
        static let needsAttention = Color.orange
        static let stale = Color.gray
        static let missing = Color.red
        
        static func background(_ status: String) -> Color {
            switch status.lowercased() {
            case "healthy": return healthy.opacity(Opacity.ultraLight)
            case "needsattention", "needs_attention": return needsAttention.opacity(Opacity.light)
            case "stale": return Color.gray.opacity(Opacity.light)
            case "missing": return missing.opacity(Opacity.light)
            default: return .clear
            }
        }
    }
}
