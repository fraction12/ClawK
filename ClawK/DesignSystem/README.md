# ClawK Design System

**Version:** 2.0.0  
**Last Updated:** 2026-02-05

## Overview

The ClawK Design System provides a consistent, maintainable foundation for all UI components in the app. It enforces visual consistency through centralized tokens for colors, typography, spacing, and animations.

## File Structure

```
DesignSystem/
├── Colors.swift          # Color tokens and semantic colors
├── Typography.swift      # Font styles and text modifiers
├── Spacing.swift         # Spacing scale and layout constants
├── DesignSystem.swift    # Utility components and animations
└── Components/
    ├── DSCard.swift      # Card variants
    ├── DSHeader.swift    # Page and section headers
    ├── DSButton.swift    # Button styles
    ├── DSStatusBadge.swift   # Status indicators
    ├── DSChart.swift     # Chart components
    ├── DSListItem.swift  # List item styles
    └── DSEmptyState.swift    # Empty state displays
```

## Quick Start

### Colors

```swift
// Semantic colors (adapt to light/dark mode)
Color.Semantic.success    // Green
Color.Semantic.warning    // Orange
Color.Semantic.error      // Red
Color.Semantic.info       // Blue
Color.Semantic.neutral    // Gray

// Surface colors
Color.Surface.primary     // Window background
Color.Surface.secondary   // Card background
Color.Surface.tertiary    // Text fields

// Text colors
Color.Text.primary
Color.Text.secondary
Color.Text.tertiary

// Create background variants
color.backgroundLight     // 10% opacity
color.backgroundMedium    // 15% opacity
color.backgroundStrong    // 30% opacity
```

### Typography

```swift
// Display (headers)
.font(.ClawK.displayLarge)    // 28pt bold rounded
.font(.ClawK.displayEmoji)    // 36pt emoji

// Body text
.font(.ClawK.body)            // Standard body
.font(.ClawK.bodyMono)        // Monospaced body
.font(.ClawK.label)           // Subheadline

// Captions
.font(.ClawK.caption)         // Caption
.font(.ClawK.captionSmall)    // Caption2

// Numbers
.font(.ClawK.numberLarge)     // Large mono bold
.font(.ClawK.numberMedium)    // Medium mono
.font(.ClawK.valueLarge)      // Title3 rounded semibold

// Text modifiers
.pageTitle()                   // Large rounded title
.pageSubtitle()                // Secondary subtitle
.cardHeaderTitle(color)        // Card header style
.metadataStyle()               // Caption secondary
```

### Spacing

```swift
// Scale (4pt grid)
Spacing.xxs   // 2pt
Spacing.xs    // 4pt
Spacing.sm    // 6pt
Spacing.md    // 8pt
Spacing.lg    // 12pt
Spacing.xl    // 16pt
Spacing.xxl   // 20pt
Spacing.page  // 24pt

// Component spacing
Spacing.Card.padding          // 16pt
Spacing.Card.contentSpacing   // 12pt
Spacing.Card.cornerRadius     // 12pt

// View modifiers
.pagePadding()                // 24pt padding
.cardPadding()                // 16pt padding
.cardBackground()             // Card styling
```

### Animations

```swift
// Standard animations
DSAnimation.instant           // 0.1s
DSAnimation.fast              // 0.2s
DSAnimation.standard          // 0.3s
DSAnimation.slow              // 0.5s

// Spring animations
DSAnimation.springBouncy
DSAnimation.springSmooth
DSAnimation.springStiff

// View modifiers
.hoverAnimation(isHovered)
.pressAnimation(isPressed)
.loadingPulse(isLoading)
```

## Components

### DSCard

The primary container component.

```swift
// Standard card
DSCard(title: "📊 STATUS", color: .purple, tooltip: "Card tooltip") {
    // Content
}

// With loading state
DSCard(title: "📊 STATUS", color: .purple, isLoading: true) {
    // Content
}

// Compact variant
DSCardCompact(title: "COMPACT", color: .blue) {
    // Content
}

// Expandable variant
DSCardExpandable(title: "📁 DETAILS", color: .green) {
    // Content
}

// With status indicator
DSCardWithStatus(title: "⚡ STATUS", color: .orange, status: .success) {
    // Content
}

// Stat card for grids
DSStatCard(label: "Tokens", value: "45K", icon: "number", color: .blue)
```

### DSPageHeader

Page-level headers.

```swift
// Basic header
DSPageHeader(emoji: "🦞", title: "CLAWK", subtitle: "Mission Control")

// With timestamp
DSPageHeaderWithTime(emoji: "🧠", title: "MEMORY", subtitle: "Browser", lastUpdated: Date())

// With custom trailing
DSPageHeader(
    emoji: "🖼️",
    title: "Canvas",
    subtitle: "Visual Display",
    trailing: AnyView(RefreshButton())
)
```

### DSStatusBadge

Status indicators and badges.

```swift
// Connection badge
DSConnectionBadge(isConnected: true)

// Model badge
DSModelBadge(modelName: "claude-sonnet-4-5")

// Config badge
DSConfigBadge(isConfigured: true)

// Custom badge
DSCustomBadge(label: "Active", color: .green, icon: "bolt.fill")

// Tier badge
DSTierBadge(tier: .hot)
```

### DSButton

Button styles and presets.

```swift
// Primary button
Button("Save") { }
    .primaryStyle(color: .teal)

// Secondary button
Button("Cancel") { }
    .secondaryStyle(color: .gray)

// Ghost button
Button("Learn More") { }
    .ghostStyle()

// Pill button
Button("All") { }
    .pillStyle(color: .blue, active: true)

// Icon buttons
DSRefreshButton(action: refresh, isRefreshing: isLoading)
DSSaveButton(action: save)
DSResetButton(action: reset)
```

### DSInfoRow

Key-value display rows.

```swift
DSInfoRow(icon: "brain", label: "Model", value: "claude-sonnet", valueColor: .purple, mono: true)
```

### DSProgressBar

Progress indicators.

```swift
// Basic
DSProgressBar(percent: 75)

// With custom color
DSProgressBar(percent: 50, color: .purple, height: 12, showLabel: true)
```

### DSEmptyState

Empty state displays.

```swift
DSEmptyState(
    icon: "tray",
    title: "No items",
    subtitle: "Nothing to show here",
    action: { refresh() },
    actionLabel: "Refresh"
)
```

## Migration Guide

### From Hardcoded Colors

```swift
// Before
.foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.3))
.background(Color(nsColor: .controlBackgroundColor))

// After
.foregroundColor(Color.Semantic.success)
.background(Color.Surface.secondary)
```

### From Hardcoded Spacing

```swift
// Before
.padding(16)
.cornerRadius(12)
VStack(spacing: 20)

// After
.padding(Spacing.xl)
.cornerRadius(Spacing.Card.cornerRadius)
VStack(spacing: Spacing.xxl)
```

### From Custom Cards

```swift
// Legacy DashboardCard has been removed (as of Feb 2026)
// Use DSCard directly:
DSCard(title: "📊 STATUS", color: .purple, tooltip: "...") {
    // Content
}
```

### From Hardcoded Fonts

```swift
// Before
.font(.system(size: 28, weight: .bold, design: .rounded))
.font(.system(.caption, design: .monospaced))

// After
.font(.ClawK.displayLarge)
.font(.ClawK.numberSmall)
```

## Best Practices

1. **Always use semantic colors** - Never hardcode RGB values
2. **Use Spacing tokens** - Maintain consistent spacing throughout
3. **Use DS components** - Prefer DSCard, DSButton, etc. over custom implementations
4. **Animate with tokens** - Use DSAnimation for consistent motion
5. **Test dark mode** - All semantic colors adapt automatically

## Component Checklist

When creating new views:

- [ ] Use `Color.Surface.primary` for main background
- [ ] Use `DSCard` for card containers
- [ ] Use `DSPageHeader` for page headers
- [ ] Use `Spacing` tokens for all padding/gaps
- [ ] Use `Font.ClawK` for typography
- [ ] Use `DSAnimation` for transitions
- [ ] Test in both light and dark mode
