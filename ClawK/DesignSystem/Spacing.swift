//
//  Spacing.swift
//  ClawK
//
//  Centralized spacing system based on 4pt grid
//  Part of Design System - Round 4
//

import SwiftUI

// MARK: - Spacing Scale

/// Spacing values based on 4pt grid system
enum Spacing {
    /// 2pt - Minimal spacing
    static let xxs: CGFloat = 2
    
    /// 4pt - Tight spacing (inline elements)
    static let xs: CGFloat = 4
    
    /// 6pt - Small badge padding
    static let sm: CGFloat = 6
    
    /// 8pt - Compact spacing (between related items)
    static let md: CGFloat = 8
    
    /// 12pt - Standard component spacing
    static let lg: CGFloat = 12
    
    /// 16pt - Card internal padding
    static let xl: CGFloat = 16
    
    /// 20pt - Section spacing
    static let xxl: CGFloat = 20
    
    /// 24pt - Page padding
    static let page: CGFloat = 24
    
    /// 32pt - Large section gaps
    static let section: CGFloat = 32
    
    /// 40pt - Empty state padding
    static let empty: CGFloat = 40
}

// MARK: - Component-Specific Spacing

extension Spacing {
    
    // MARK: - Card
    struct Card {
        static let padding: CGFloat = Spacing.xl          // 16pt
        static let contentSpacing: CGFloat = Spacing.lg   // 12pt
        static let cornerRadius: CGFloat = 12
    }
    
    // MARK: - Badge
    struct Badge {
        static let paddingH: CGFloat = Spacing.md         // 8pt
        static let paddingV: CGFloat = Spacing.xs         // 4pt
        static let cornerRadius: CGFloat = 6
    }
    
    // MARK: - Button
    struct Button {
        static let paddingH: CGFloat = Spacing.lg         // 12pt
        static let paddingV: CGFloat = Spacing.md         // 8pt
        static let spacing: CGFloat = Spacing.md          // 8pt
    }
    
    // MARK: - List
    struct List {
        static let rowPadding: CGFloat = Spacing.md       // 8pt
        static let rowSpacing: CGFloat = Spacing.md       // 8pt
        static let iconSize: CGFloat = Spacing.xl         // 16pt
    }
    
    // MARK: - Form
    struct Form {
        static let fieldSpacing: CGFloat = Spacing.xl     // 16pt
        static let labelSpacing: CGFloat = Spacing.md     // 8pt
        static let inputPadding: CGFloat = 10
    }
    
    // MARK: - Header
    struct Header {
        static let iconSize: CGFloat = 36
        static let iconSpacing: CGFloat = Spacing.lg      // 12pt
        static let titleSpacing: CGFloat = Spacing.xxs    // 2pt
        static let bottomMargin: CGFloat = Spacing.md     // 8pt
    }
    
    // MARK: - Grid
    struct Grid {
        static let columns: CGFloat = Spacing.xxl         // 20pt
        static let rows: CGFloat = Spacing.lg             // 12pt
    }
    
    // MARK: - Chart
    struct Chart {
        static let height: CGFloat = 80
        static let heightLarge: CGFloat = 120
        static let padding: CGFloat = Spacing.md          // 8pt
    }
    
    // MARK: - Progress
    struct Progress {
        static let heightSmall: CGFloat = 6
        static let heightMedium: CGFloat = 8
        static let heightLarge: CGFloat = 12
    }
    
    // MARK: - Status Indicator
    struct StatusIndicator {
        static let dotSmall: CGFloat = 8
        static let dotLarge: CGFloat = 10
        static let spacing: CGFloat = Spacing.sm          // 6pt
    }
}

// MARK: - Layout Constants

extension Spacing {
    struct Layout {
        /// Minimum width for side-by-side layout
        static let twoColumnBreakpoint: CGFloat = 800
        
        /// Wide breakpoint
        static let wideBreakpoint: CGFloat = 900
        
        /// Minimum column width
        static let columnMinWidth: CGFloat = 350
        
        /// Maximum card content height
        static let cardMaxHeight: CGFloat = 700
        
        /// Minimum card content height
        static let cardMinHeight: CGFloat = 400
        
        /// Popover width
        static let popoverWidth: CGFloat = 240
    }
}

// MARK: - Convenience Extensions

extension View {
    /// Standard page padding
    func pagePadding() -> some View {
        self.padding(Spacing.page)
    }
    
    /// Standard card padding
    func cardPadding() -> some View {
        self.padding(Spacing.Card.padding)
    }
    
    /// Standard section spacing
    func sectionSpacing() -> some View {
        self.padding(.bottom, Spacing.xxl)
    }
    
    /// Badge padding
    func badgePadding() -> some View {
        self.padding(.horizontal, Spacing.Badge.paddingH)
            .padding(.vertical, Spacing.Badge.paddingV)
    }
}

// MARK: - Shadow

extension Spacing {
    struct Shadow {
        static let radius: CGFloat = 5
        static let y: CGFloat = 2
    }
}
