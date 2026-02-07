//
//  MemoryTierComponents.swift
//  ClawK
//
//  Reusable tier section and row components for Memory Browser
//

import SwiftUI

// MARK: - Tier Section

struct MemoryTierSection: View {
    let tier: MemoryTier
    var files: [MemoryFile]? = nil
    var folders: [MemoryFolder]? = nil
    @ObservedObject var viewModel: MemoryViewModel
    
    private var itemCount: Int {
        (files?.count ?? 0) + (folders?.reduce(0) { $0 + $1.totalFiles } ?? 0)
    }
    
    var body: some View {
        Section {
            // Direct files
            if let files = files {
                ForEach(files) { file in
                    MemoryFileRow(file: file, viewModel: viewModel)
                }
            }
            
            // Folders
            if let folders = folders {
                ForEach(folders) { folder in
                    MemoryFolderRow(folder: folder, viewModel: viewModel)
                }
            }
        } header: {
            HStack(spacing: 10) {
                Text(tier.icon)
                    .font(.system(size: 16))
                
                Text(tier.displayName.uppercased())
                    .font(.system(.caption, design: .rounded, weight: .heavy))
                    .tracking(1.0)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(itemCount)")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(tierColor.opacity(0.25))
                    )
                    .foregroundColor(tierColor)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            .allowsHitTesting(false)
        }
        .collapsible(false)
    }
    
    var tierColor: Color {
        switch tier {
        case .hot: return Color(red: 1.0, green: 0.42, blue: 0.42)
        case .warm: return Color(red: 1.0, green: 0.65, blue: 0.15)
        case .cold: return Color(red: 0.26, green: 0.65, blue: 0.96)
        case .archive: return Color(red: 0.62, green: 0.62, blue: 0.62)
        }
    }
}

// MARK: - File Row

struct MemoryFileRow: View {
    let file: MemoryFile
    @ObservedObject var viewModel: MemoryViewModel
    
    var isSelected: Bool {
        viewModel.selectedFile?.id == file.id
    }
    
    var isMemoryMd: Bool {
        file.name == "MEMORY.md"
    }
    
    var body: some View {
        Button(action: {
            viewModel.viewMode = .browse
            Task {
                await viewModel.loadFileContent(file: file)
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: isMemoryMd ? "brain.head.profile" : "doc.text")
                    .foregroundColor(isMemoryMd ? .yellow : tierColor)
                    .font(.system(size: 13))
                    .frame(width: 20, alignment: .center)
                
                Text(file.name)
                    .font(.system(.body, weight: isMemoryMd ? .semibold : .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: 4) {
                    Text("\(file.tokens)")
                        .font(.system(.caption, design: .monospaced, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    if file.chunkCount > 0 {
                        Text("•")
                            .font(.ClawK.captionSmall)
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("\(file.chunkCount)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .frame(minWidth: 70, alignment: .trailing)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.25) :
                          isMemoryMd ? Color.yellow.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: file.path))
            } label: {
                Label("Open in External Editor", systemImage: "arrow.up.forward.square")
            }
            
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
            
            Button {
                NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "")
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            
            Divider()
            
            Button {
                Task {
                    await viewModel.loadFileContent(file: file)
                }
            } label: {
                Label("View Content", systemImage: "eye")
            }
        }
    }
    
    var tierColor: Color {
        switch file.tier {
        case .hot: return Color(red: 1.0, green: 0.42, blue: 0.42)
        case .warm: return Color(red: 1.0, green: 0.65, blue: 0.15)
        case .cold: return Color(red: 0.26, green: 0.65, blue: 0.96)
        case .archive: return Color(red: 0.62, green: 0.62, blue: 0.62)
        }
    }
}

// MARK: - Folder Row

struct MemoryFolderRow: View {
    let folder: MemoryFolder
    @ObservedObject var viewModel: MemoryViewModel
    
    var isExpanded: Bool {
        viewModel.isExpanded(folder)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                viewModel.toggleFolder(folder)
            }) {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "folder.fill" : "folder")
                        .foregroundColor(tierColor)
                        .font(.system(size: 14))
                        .frame(width: 20, alignment: .center)
                    
                    Text(folder.name)
                        .font(.system(.body))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(tierColor.opacity(0.9))
                        .frame(width: 16, alignment: .center)
                    
                    Text("\(folder.totalFiles)")
                        .font(.system(.caption, design: .monospaced, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(minWidth: 24, alignment: .trailing)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(folder.files) { file in
                        MemoryFileRow(file: file, viewModel: viewModel)
                            .padding(.leading, 24)
                    }
                    
                    ForEach(folder.subfolders) { subfolder in
                        MemoryFolderRow(folder: subfolder, viewModel: viewModel)
                            .padding(.leading, 24)
                    }
                }
            }
        }
    }
    
    var tierColor: Color {
        switch folder.tier {
        case .hot: return Color(red: 1.0, green: 0.42, blue: 0.42)
        case .warm: return Color(red: 1.0, green: 0.65, blue: 0.15)
        case .cold: return Color(red: 0.26, green: 0.65, blue: 0.96)
        case .archive: return Color(red: 0.62, green: 0.62, blue: 0.62)
        }
    }
}
