//
//  MemoryNotConfiguredView.swift
//  ClawK
//
//  Empty state shown when no memory system is detected
//

import SwiftUI

struct MemoryNotConfiguredView: View {
    
    /// Check if the memory system exists
    static var isMemoryConfigured: Bool {
        let config = AppConfiguration.shared
        let fm = FileManager.default
        let memoryPath = config.memoryPath
        let workspacePath = config.workspacePath
        let memoryMdPath = "\(workspacePath)/MEMORY.md"
        
        // Check if either memory/ dir or MEMORY.md exists
        let hasMemoryDir = fm.fileExists(atPath: memoryPath)
        let hasMemoryMd = fm.fileExists(atPath: memoryMdPath)
        
        return hasMemoryDir || hasMemoryMd
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                DSPageHeader(
                    emoji: "🧠",
                    title: "Memory",
                    subtitle: "Agent memory system"
                )
                
                VStack(spacing: 32) {
                    // Hero
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.1))
                                .frame(width: 100, height: 100)
                            
                            Image(systemName: "brain")
                                .font(.system(size: 44))
                                .foregroundColor(.accentColor.opacity(0.6))
                        }
                        
                        Text("Memory System Not Detected")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text("ClawK can monitor your agent's memory — but no memory system was found in your workspace.")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 450)
                    }
                    
                    // Why use a memory system
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Why give your agent memory?")
                        
                        BenefitRow(
                            icon: "arrow.trianglehead.2.counterclockwise",
                            title: "Persistence across sessions",
                            description: "Without memory, your agent starts fresh every conversation. With memory, it remembers decisions, preferences, and context."
                        )
                        
                        BenefitRow(
                            icon: "brain.head.profile",
                            title: "Learns over time",
                            description: "Your agent builds a knowledge base — what worked, what didn't, your preferences, important facts. It gets better the more you use it."
                        )
                        
                        BenefitRow(
                            icon: "tray.full",
                            title: "Tiered storage",
                            description: "Hot memory (recent, always loaded) → warm (this month) → cold (archived summaries). Keeps context small but knowledge deep."
                        )
                        
                        BenefitRow(
                            icon: "clock.arrow.circlepath",
                            title: "Automated maintenance",
                            description: "Set up cron jobs to curate, archive, and compress memory automatically. Your agent stays sharp without manual cleanup."
                        )
                    }
                    .padding(24)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(16)
                    
                    // How to set it up
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "How to set it up")
                        
                        SetupStep(
                            number: 1,
                            title: "Create a MEMORY.md in your workspace",
                            code: "touch ~/.openclaw/workspace/MEMORY.md",
                            description: "This is your agent's hot memory — curated facts, preferences, and key context loaded every session."
                        )
                        
                        SetupStep(
                            number: 2,
                            title: "Create the memory directory",
                            code: "mkdir -p ~/.openclaw/workspace/memory",
                            description: "Daily logs, archives, and tiered storage live here."
                        )
                        
                        SetupStep(
                            number: 3,
                            title: "Tell your agent about the structure",
                            description: "Add instructions to your AGENTS.md explaining the memory tiers: hot (MEMORY.md + last 7 daily logs), warm (current month), cold (monthly summaries), archive (quarterly rollups)."
                        )
                        
                        SetupStep(
                            number: 4,
                            title: "Set up curation crons (optional)",
                            description: "Create cron jobs for daily curation (extract learnings → MEMORY.md), weekly maintenance (move old logs to month folders), and monthly compression (summarize into archives). Name them with keywords like \"daily curation\" so ClawK can track them."
                        )
                    }
                    .padding(24)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(16)
                    
                    // Example structure
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Example structure")
                        
                        Text("""
                        workspace/
                        ├── MEMORY.md              # 🔥 Hot: curated permanent knowledge
                        ├── memory/
                        │   ├── 2026-02-06.md      # 🔥 Hot: today's log
                        │   ├── 2026-02-05.md      # 🔥 Hot: recent days
                        │   ├── 2026-02/           # 🟡 Warm: older this month
                        │   ├── 2026-01/           # 🟡 Warm: last month
                        │   └── archive/
                        │       ├── 2026-01-summary.md  # 🧊 Cold: monthly summary
                        │       └── 2026-Q1.md          # 📦 Archive: quarterly rollup
                        """)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(8)
                    }
                    .padding(24)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(16)
                    
                    // What ClawK monitors
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "What ClawK monitors")
                        
                        Text("Once your memory system is set up, ClawK shows you:")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        
                        MonitorItem(text: "Context pressure — how full your agent's context window is")
                        MonitorItem(text: "Memory files — status, size, and token counts per file")
                        MonitorItem(text: "Archive health — tier distribution and storage stats")
                        MonitorItem(text: "Curation schedule — when automated maintenance runs")
                        MonitorItem(text: "Memory activity — searches, writes, and active files")
                        MonitorItem(text: "File browser — preview and navigate your entire memory tree")
                    }
                    .padding(24)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(16)
                }
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .pagePadding()
        }
        .background(Color.Surface.primary)
    }
}

// MARK: - Subviews

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
    }
}

private struct BenefitRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.accentColor)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SetupStep: View {
    let number: Int
    let title: String
    var code: String? = nil
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.15))
                .cornerRadius(14)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                
                if let code = code {
                    Text(code)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.green.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                }
                
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct MonitorItem: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.green)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
        }
    }
}
