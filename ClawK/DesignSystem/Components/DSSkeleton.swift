//
//  DSSkeleton.swift
//  ClawK
//
//  Design System skeleton/ghost loading components
//  Part of Design System - Standardized loading states
//

import SwiftUI

// MARK: - Base Skeleton Box with Shimmer Animation

struct SkeletonBox: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat
    
    @State private var shimmerOffset: CGFloat = -1.0
    
    init(width: CGFloat? = nil, height: CGFloat = 20, cornerRadius: CGFloat = 4) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.15))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .cornerRadius(cornerRadius)
            .overlay(
                GeometryReader { geometry in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .white.opacity(0.3),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * 0.3)
                        .offset(x: shimmerOffset * geometry.size.width)
                }
                .mask(
                    RoundedRectangle(cornerRadius: cornerRadius)
                )
            )
            .clipped()
            .onAppear {
                withAnimation(
                    .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    shimmerOffset = 2.0
                }
            }
    }
}

// MARK: - Skeleton Text Lines

struct SkeletonText: View {
    let lines: Int
    let lineHeight: CGFloat
    let spacing: CGFloat
    let lastLineWidth: CGFloat
    
    init(lines: Int = 1, lineHeight: CGFloat = 16, spacing: CGFloat = 8, lastLineWidth: CGFloat = 0.7) {
        self.lines = lines
        self.lineHeight = lineHeight
        self.spacing = spacing
        self.lastLineWidth = lastLineWidth
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<lines, id: \.self) { index in
                GeometryReader { geo in
                    SkeletonBox(
                        width: index == lines - 1 && lines > 1 ? geo.size.width * lastLineWidth : nil,
                        height: lineHeight
                    )
                }
                .frame(height: lineHeight)
            }
        }
    }
}

// MARK: - Skeleton Circle

struct SkeletonCircle: View {
    let size: CGFloat
    
    @State private var shimmerOffset: CGFloat = -1.0
    
    init(size: CGFloat = 40) {
        self.size = size
    }
    
    var body: some View {
        Circle()
            .fill(Color.secondary.opacity(0.15))
            .frame(width: size, height: size)
            .overlay(
                GeometryReader { geometry in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .white.opacity(0.3),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * 0.4)
                        .offset(x: shimmerOffset * geometry.size.width)
                }
                .mask(Circle())
            )
            .clipped()
            .onAppear {
                withAnimation(
                    .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    shimmerOffset = 2.0
                }
            }
    }
}

// MARK: - Skeleton Stat Box (for Stats Card grid)

struct SkeletonStatBox: View {
    var body: some View {
        VStack(spacing: 6) {
            SkeletonCircle(size: 28) // Icon placeholder
            SkeletonBox(width: 50, height: 22, cornerRadius: 6) // Value
            SkeletonBox(width: 70, height: 12, cornerRadius: 4) // Label
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Skeleton Session Row

struct SkeletonSessionRow: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonCircle(size: 28)
            
            VStack(alignment: .leading, spacing: 4) {
                SkeletonBox(width: 140, height: 16, cornerRadius: 4)
                SkeletonBox(width: 100, height: 12, cornerRadius: 3)
            }
            
            Spacer()
            
            SkeletonBox(width: 60, height: 14, cornerRadius: 4)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Skeleton Cron Row

struct SkeletonCronRow: View {
    var body: some View {
        HStack(spacing: 10) {
            SkeletonCircle(size: 8)
            
            VStack(alignment: .leading, spacing: 4) {
                SkeletonBox(width: 120, height: 14, cornerRadius: 4)
                SkeletonBox(width: 60, height: 10, cornerRadius: 3)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                SkeletonBox(width: 70, height: 12, cornerRadius: 4)
                SkeletonBox(width: 50, height: 10, cornerRadius: 3)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }
}

// MARK: - Skeleton Heartbeat Card Content

struct SkeletonHeartbeatContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status badge
            HStack {
                SkeletonBox(width: 100, height: 28, cornerRadius: 8)
                Spacer()
                SkeletonBox(width: 80, height: 16, cornerRadius: 4)
            }
            
            // Graph placeholder
            SkeletonBox(height: 80, cornerRadius: 8)
            
            // Summary stats
            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonBox(width: 70, height: 24, cornerRadius: 6)
                }
                Spacer()
            }
            
            // Time info
            VStack(spacing: 8) {
                HStack {
                    SkeletonBox(width: 80, height: 14, cornerRadius: 4)
                    Spacer()
                    SkeletonBox(width: 100, height: 14, cornerRadius: 4)
                }
                HStack {
                    SkeletonBox(width: 80, height: 14, cornerRadius: 4)
                    Spacer()
                    SkeletonBox(width: 60, height: 14, cornerRadius: 4)
                }
            }
            
            // Recent checks
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBox(width: 90, height: 12, cornerRadius: 3)
                HStack(spacing: 4) {
                    ForEach(0..<10, id: \.self) { _ in
                        SkeletonCircle(size: 10)
                    }
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Skeleton Quota Card Content

struct SkeletonQuotaContent: View {
    var body: some View {
        VStack(spacing: 16) {
            // Header row
            HStack {
                SkeletonBox(width: 100, height: 24, cornerRadius: 6)
                Spacer()
                SkeletonBox(width: 60, height: 24, cornerRadius: 6)
            }
            
            // Session window
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SkeletonBox(width: 80, height: 14, cornerRadius: 4)
                    Spacer()
                    SkeletonBox(width: 60, height: 20, cornerRadius: 4)
                }
                SkeletonBox(height: 8, cornerRadius: 4) // Progress bar
                SkeletonBox(width: 120, height: 12, cornerRadius: 3)
            }
            
            Divider()
            
            // Weekly window
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SkeletonBox(width: 80, height: 14, cornerRadius: 4)
                    Spacer()
                    SkeletonBox(width: 60, height: 20, cornerRadius: 4)
                }
                SkeletonBox(height: 8, cornerRadius: 4) // Progress bar
                HStack(spacing: 12) {
                    SkeletonBox(width: 120, height: 12, cornerRadius: 3)
                    SkeletonBox(width: 80, height: 12, cornerRadius: 3)
                }
            }
            
            Divider()
            
            // Footer
            HStack {
                SkeletonBox(width: 40, height: 16, cornerRadius: 4)
                Spacer()
                SkeletonBox(width: 24, height: 24, cornerRadius: 4)
            }
        }
    }
}

// MARK: - Skeleton Context Pressure Content

struct SkeletonContextPressureContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with status
            HStack {
                SkeletonBox(width: 80, height: 28, cornerRadius: 8)
                Spacer()
            }
            
            // Telegram session
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    SkeletonBox(width: 100, height: 12, cornerRadius: 3)
                    Spacer()
                    SkeletonBox(width: 50, height: 20, cornerRadius: 4)
                }
                
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    SkeletonBox(width: 80, height: 28, cornerRadius: 6)
                    SkeletonBox(width: 60, height: 20, cornerRadius: 4)
                }
            }
            
            // Progress bar
            SkeletonBox(height: 16, cornerRadius: 6)
            
            // Threshold labels
            SkeletonBox(height: 14, cornerRadius: 3)
            
            Divider()
            
            // Main session
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    SkeletonBox(width: 80, height: 12, cornerRadius: 3)
                    Spacer()
                    SkeletonBox(width: 50, height: 16, cornerRadius: 4)
                }
                
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    SkeletonBox(width: 60, height: 20, cornerRadius: 4)
                    SkeletonBox(width: 50, height: 14, cornerRadius: 3)
                }
                
                SkeletonBox(height: 12, cornerRadius: 4)
            }
            
            Divider()
            
            // Last compaction
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    SkeletonBox(width: 100, height: 12, cornerRadius: 3)
                    SkeletonBox(width: 80, height: 16, cornerRadius: 4)
                }
                Spacer()
            }
            
            // Auto-compaction info
            SkeletonBox(height: 60, cornerRadius: 8)
        }
    }
}

// MARK: - Skeleton Memory File Row

struct SkeletonMemoryFileRow: View {
    var body: some View {
        HStack {
            SkeletonCircle(size: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                SkeletonBox(width: 140, height: 14, cornerRadius: 4)
                HStack(spacing: 8) {
                    SkeletonBox(width: 50, height: 10, cornerRadius: 3)
                    SkeletonBox(width: 70, height: 10, cornerRadius: 3)
                }
            }
            
            Spacer()
            
            SkeletonBox(width: 60, height: 12, cornerRadius: 4)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Skeleton File Tree Item

struct SkeletonFileTreeItem: View {
    let indent: CGFloat
    
    init(indent: CGFloat = 0) {
        self.indent = indent
    }
    
    var body: some View {
        HStack(spacing: 8) {
            SkeletonBox(width: 16, height: 16, cornerRadius: 3)
            SkeletonBox(width: CGFloat.random(in: 100...180), height: 14, cornerRadius: 4)
            Spacer()
        }
        .padding(.leading, indent)
        .padding(.vertical, 4)
    }
}

// MARK: - Skeleton Connection Status

struct SkeletonConnectionStatus: View {
    var body: some View {
        HStack(spacing: 6) {
            SkeletonCircle(size: 8)
            SkeletonBox(width: 80, height: 14, cornerRadius: 4)
        }
    }
}

// MARK: - Loading Transition Modifier

struct SkeletonTransition: ViewModifier {
    let isLoading: Bool
    
    func body(content: Content) -> some View {
        content
            .opacity(isLoading ? 0 : 1)
            .animation(.easeInOut(duration: 0.3), value: isLoading)
    }
}

extension View {
    func skeletonTransition(isLoading: Bool) -> some View {
        modifier(SkeletonTransition(isLoading: isLoading))
    }
}
