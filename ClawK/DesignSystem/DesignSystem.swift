//
//  DesignSystem.swift
//  ClawK
//
//  Main design system entry point
//  Part of Design System - Round 5
//
//  This file re-exports all design tokens and provides utility components.
//  Import hierarchy:
//    - Colors.swift: Color.Semantic, Color.Accent, Color.CardHeader, etc.
//    - Typography.swift: Font.ClawK, text style modifiers
//    - Spacing.swift: Spacing enum, component-specific spacing
//

import SwiftUI

// MARK: - Design System Version

enum DesignSystem {
    static let version = "2.0.0"
    static let lastUpdated = "2026-02-05"
}

// MARK: - Animation Tokens (Round 22)

enum DSAnimation {
    /// Standard durations
    enum Duration {
        static let instant: Double = 0.1
        static let fast: Double = 0.2
        static let normal: Double = 0.3
        static let slow: Double = 0.5
        static let verySlow: Double = 1.0
    }
    
    /// Standard animations
    static let instant = Animation.easeInOut(duration: Duration.instant)
    static let fast = Animation.easeInOut(duration: Duration.fast)
    static let standard = Animation.easeInOut(duration: Duration.normal)
    static let slow = Animation.easeInOut(duration: Duration.slow)
    
    /// Spring animations
    static let springBouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)
    static let springSmooth = Animation.spring(response: 0.5, dampingFraction: 0.8)
    static let springStiff = Animation.spring(response: 0.3, dampingFraction: 0.9)
    
    /// Interactive animations
    static let buttonPress = Animation.easeOut(duration: Duration.instant)
    static let cardHover = Animation.easeInOut(duration: Duration.fast)
    static let expand = Animation.easeInOut(duration: Duration.normal)
    static let collapse = Animation.easeInOut(duration: Duration.fast)
    
    /// Loading animations
    static let pulse = Animation.easeInOut(duration: Duration.verySlow).repeatForever(autoreverses: true)
    static let spin = Animation.linear(duration: Duration.verySlow).repeatForever(autoreverses: false)
    static let shimmer = Animation.linear(duration: 1.5).repeatForever(autoreverses: false)
}

// MARK: - Animation View Extensions

extension View {
    /// Apply standard hover animation
    func hoverAnimation(_ isHovered: Bool) -> some View {
        self
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .shadow(
                color: isHovered ? Color.black.opacity(0.1) : Color.black.opacity(0.05),
                radius: isHovered ? 8 : 5,
                y: isHovered ? 4 : 2
            )
            .animation(DSAnimation.cardHover, value: isHovered)
    }
    
    /// Apply press animation
    func pressAnimation(_ isPressed: Bool) -> some View {
        self
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .opacity(isPressed ? 0.8 : 1.0)
            .animation(DSAnimation.buttonPress, value: isPressed)
    }
    
    /// Apply loading pulse
    func loadingPulse(_ isLoading: Bool) -> some View {
        self
            .opacity(isLoading ? 0.5 : 1.0)
            .animation(isLoading ? DSAnimation.pulse : .default, value: isLoading)
    }
}

// MARK: - Standard Shadows

extension View {
    /// Standard card shadow
    func cardShadow() -> some View {
        self.shadow(
            color: Color.Shadow.color,
            radius: Spacing.Shadow.radius,
            x: 0,
            y: Spacing.Shadow.y
        )
    }
}

// MARK: - Standard Card Background

extension View {
    /// Standard card background styling
    func cardBackground() -> some View {
        self
            .background(Color.Surface.secondary)
            .cornerRadius(Spacing.Card.cornerRadius)
            .cardShadow()
    }
}

// MARK: - Standard Badge

struct DSBadge: View {
    let text: String
    let color: Color
    var style: Style = .filled
    
    enum Style {
        case filled
        case outlined
    }
    
    var body: some View {
        Text(text)
            .font(.ClawK.badgeBold)
            .foregroundColor(style == .filled ? color : color)
            .padding(.horizontal, Spacing.Badge.paddingH)
            .padding(.vertical, Spacing.Badge.paddingV)
            .background(
                Group {
                    if style == .filled {
                        color.backgroundMedium
                    } else {
                        Color.clear
                    }
                }
            )
            .overlay(
                Group {
                    if style == .outlined {
                        RoundedRectangle(cornerRadius: Spacing.Badge.cornerRadius)
                            .stroke(color.opacity(0.5), lineWidth: 1)
                    }
                }
            )
            .cornerRadius(Spacing.Badge.cornerRadius)
    }
}

// MARK: - Standard Status Dot

struct DSStatusDot: View {
    let color: Color
    var size: Size = .medium
    var animated: Bool = false
    
    enum Size {
        case small, medium, large
        
        var dimension: CGFloat {
            switch self {
            case .small: return 6
            case .medium: return 8
            case .large: return 10
            }
        }
    }
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size.dimension, height: size.dimension)
            .overlay(
                Group {
                    if animated {
                        Circle()
                            .stroke(color.opacity(0.5), lineWidth: 2)
                            .scaleEffect(1.5)
                            .opacity(0)
                            .animation(
                                .easeOut(duration: 1.0).repeatForever(autoreverses: false),
                                value: animated
                            )
                    }
                }
            )
    }
}

// MARK: - Standard Progress Bar

struct DSProgressBar: View {
    let percent: Double
    var color: Color? = nil
    var height: CGFloat = Spacing.Progress.heightMedium
    var showLabel: Bool = false
    
    private var barColor: Color {
        color ?? Color.Progress.forPercent(percent)
    }
    
    var body: some View {
        VStack(alignment: .trailing, spacing: Spacing.xs) {
            if showLabel {
                Text(String(format: "%.0f%%", min(percent, 100)))
                    .font(.ClawK.captionSmall)
                    .foregroundColor(barColor)
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(Color.gray.opacity(Color.Opacity.normal))
                        .frame(height: height)
                    
                    // Progress
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(barColor)
                        .frame(width: geo.size.width * CGFloat(min(percent, 100) / 100), height: height)
                }
            }
            .frame(height: height)
        }
    }
}

// MARK: - Standard Divider

struct DSDivider: View {
    var color: Color = Color.Border.subtle
    var height: CGFloat = 1
    
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: height)
    }
}

// MARK: - Standard Icon

struct DSIcon: View {
    let systemName: String
    var color: Color = .secondary
    var size: Size = .medium
    
    enum Size {
        case small, medium, large, xlarge
        
        var font: Font {
            switch self {
            case .small: return .caption
            case .medium: return .body
            case .large: return .title2
            case .xlarge: return .title
            }
        }
    }
    
    var body: some View {
        Image(systemName: systemName)
            .font(size.font)
            .foregroundColor(color)
    }
}

// MARK: - Standard Empty State

struct DSEmptyState: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var action: (() -> Void)? = nil
    var actionLabel: String = "Retry"
    
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(Color.Text.tertiary)
                    .multilineTextAlignment(.center)
            }
            
            if let action = action {
                Button(action: action) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text(actionLabel)
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(Spacing.empty)
    }
}

// MARK: - Standard Info Row

struct DSInfoRow: View {
    let icon: String?
    let label: String
    let value: String
    var valueColor: Color = .primary
    var mono: Bool = false
    
    init(icon: String? = nil, label: String, value: String, valueColor: Color = .primary, mono: Bool = false) {
        self.icon = icon
        self.label = label
        self.value = value
        self.valueColor = valueColor
        self.mono = mono
    }
    
    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 16)
            }
            
            Text(label)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(mono ? .ClawK.bodyMono : .body)
                .foregroundColor(valueColor)
        }
    }
}

// MARK: - Preview Support

#if DEBUG
struct DesignSystemPreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                // Colors
                Text("Colors").font(.headline)
                HStack {
                    Circle().fill(Color.Semantic.success).frame(width: 24)
                    Circle().fill(Color.Semantic.warning).frame(width: 24)
                    Circle().fill(Color.Semantic.error).frame(width: 24)
                    Circle().fill(Color.Semantic.info).frame(width: 24)
                }
                
                // Badges
                Text("Badges").font(.headline)
                HStack {
                    DSBadge(text: "Success", color: .green)
                    DSBadge(text: "Warning", color: .orange)
                    DSBadge(text: "Error", color: .red)
                }
                
                // Progress
                Text("Progress Bars").font(.headline)
                DSProgressBar(percent: 25)
                DSProgressBar(percent: 65)
                DSProgressBar(percent: 90)
                
                // Status Dots
                Text("Status Dots").font(.headline)
                HStack {
                    DSStatusDot(color: .green, size: .small)
                    DSStatusDot(color: .orange, size: .medium)
                    DSStatusDot(color: .red, size: .large)
                }
                
                // Empty State
                Text("Empty State").font(.headline)
                DSEmptyState(
                    icon: "tray",
                    title: "No items",
                    subtitle: "Nothing to show here"
                )
            }
            .padding()
        }
    }
}

#Preview {
    DesignSystemPreview()
}
#endif

// MARK: - Debug Logging

/// Debug-only print helper — compiles to no-op in release builds
@inline(__always)
func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}

// MARK: - Token Formatting Extension

extension Int {
    /// Format token count for display (e.g., "1.2M", "150K", "500")
    var formattedTokens: String {
        if self >= 1_000_000 {
            return String(format: "%.1fM", Double(self) / 1_000_000)
        } else if self >= 1_000 {
            return String(format: "%.0fK", Double(self) / 1_000)
        }
        return "\(self)"
    }
}
