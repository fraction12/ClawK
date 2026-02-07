//
//  Typography.swift
//  ClawK
//
//  Centralized typography system
//  Part of Design System - Round 3
//

import SwiftUI

// MARK: - Typography Scale

extension Font {
    
    struct ClawK {
        // MARK: - Display (Headers)
        
        /// Large page title - 28pt bold rounded (e.g., "CLAWK", "MEMORY")
        static let displayLarge = Font.system(size: 28, weight: .bold, design: .rounded)
        
        /// Section header emoji - 36pt
        static let displayEmoji = Font.system(size: 36)
        
        // MARK: - Titles
        
        /// Card title - headline rounded (e.g., "⚡ ACTIVE NOW")
        static let cardTitle = Font.system(.headline, design: .rounded)
        
        /// Large value display - title3 rounded semibold
        static let valueLarge = Font.system(.title3, design: .rounded, weight: .semibold)
        
        /// Medium value display - title3 monospaced semibold
        static let valueMono = Font.system(.title3, design: .monospaced, weight: .semibold)
        
        // MARK: - Body
        
        /// Primary body text
        static let body = Font.body
        
        /// Monospaced body (URLs, tokens, code)
        static let bodyMono = Font.system(.body, design: .monospaced)
        
        /// Headline weight body
        static let bodyBold = Font.headline
        
        // MARK: - Labels
        
        /// Subheadline for secondary info
        static let label = Font.subheadline
        
        /// Caption for metadata
        static let caption = Font.caption
        
        /// Smaller caption
        static let captionSmall = Font.caption2
        
        // MARK: - Monospaced Values
        
        /// Large monospaced number
        static let numberLarge = Font.system(.title2, design: .monospaced, weight: .bold)
        
        /// Medium monospaced number
        static let numberMedium = Font.system(.headline, design: .monospaced)
        
        /// Small monospaced number
        static let numberSmall = Font.system(.caption, design: .monospaced, weight: .medium)
        
        // MARK: - Badges
        
        /// Badge text
        static let badge = Font.caption
        
        /// Badge text bold
        static let badgeBold = Font.system(.caption, weight: .medium)
    }
}

// MARK: - Text Styles

extension View {
    /// Page title style (e.g., "CLAWK", "MEMORY")
    func pageTitle() -> some View {
        self.font(.ClawK.displayLarge)
            .foregroundColor(.primary)
    }
    
    /// Page subtitle style
    func pageSubtitle() -> some View {
        self.font(.subheadline)
            .foregroundColor(.secondary)
    }
    
    /// Card header title style
    func cardHeaderTitle(_ color: Color) -> some View {
        self.font(.ClawK.cardTitle)
            .foregroundColor(color)
    }
    
    /// Monospaced value style
    func monoValue() -> some View {
        self.font(.ClawK.valueMono)
    }
    
    /// Large value display style
    func largeValue() -> some View {
        self.font(.ClawK.valueLarge)
    }
    
    /// Caption/metadata style
    func metadataStyle() -> some View {
        self.font(.ClawK.caption)
            .foregroundColor(.secondary)
    }
    
    /// Badge label style
    func badgeStyle(_ color: Color) -> some View {
        self.font(.ClawK.badgeBold)
            .foregroundColor(color)
    }
}

// MARK: - Line Heights (for custom layouts)

extension CGFloat {
    struct LineHeight {
        static let display: CGFloat = 34
        static let title: CGFloat = 24
        static let body: CGFloat = 20
        static let caption: CGFloat = 16
    }
}
