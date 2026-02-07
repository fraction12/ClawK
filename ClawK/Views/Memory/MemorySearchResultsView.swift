//
//  MemorySearchResultsView.swift
//  ClawK
//
//  View for displaying search results
//

import SwiftUI

struct MemorySearchResultsView: View {
    @ObservedObject var viewModel: MemoryViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            if viewModel.searchQuery.isEmpty {
                // No search query
                EmptySearchStateView()
            } else if viewModel.isSearching {
                // Full-screen loading state with visual feedback
                VStack(spacing: Spacing.xl) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding(.bottom, Spacing.md)
                    
                    Text("Searching...")
                        .font(.ClawK.bodyBold)
                    
                    Text("Looking through \(viewModel.memoryStructure.allFiles.count) files")
                        .font(.ClawK.caption)
                        .foregroundColor(.secondary)
                    
                    // Animated dots to show activity
                    HStack(spacing: Spacing.xs) {
                        ForEach(0..<3) { i in
                            Circle()
                                .fill(Color.Accent.model.opacity(0.6))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.Surface.secondary.opacity(0.3))
            } else if viewModel.searchResults.isEmpty {
                // No results
                NoResultsView(query: viewModel.searchQuery)
            } else {
                // Results list
                SearchResultsListView(viewModel: viewModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Empty State

struct EmptySearchStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("Search Your Memory")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Enter a query to search across all your memory files.\nSearches both content and semantic meaning.")
                .font(.ClawK.label)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Try searching for:")
                    .font(.ClawK.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    SuggestionChip(text: "decisions")
                    SuggestionChip(text: "things built")
                    SuggestionChip(text: "learnings")
                }
            }
            .padding(.top, 8)
        }
        .padding(40)
    }
}

struct SuggestionChip: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.ClawK.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.1))
            .foregroundColor(.accentColor)
            .cornerRadius(16)
    }
}

// MARK: - No Results

struct NoResultsView: View {
    let query: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("No Results Found")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("No memory files match \"\(query)\"")
                .font(.ClawK.label)
                .foregroundColor(.secondary)
        }
        .padding(40)
    }
}

// MARK: - Results List

struct SearchResultsListView: View {
    @ObservedObject var viewModel: MemoryViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Results header
            HStack {
                Text("\(viewModel.searchResults.count) \(viewModel.searchResults.count == 1 ? "result" : "results")")
                    .font(.ClawK.bodyBold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("for \"\(viewModel.searchQuery)\"")
                    .font(.ClawK.label)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            
            // Results
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.searchResults) { result in
                        SearchResultCard(result: result, query: viewModel.searchQuery)
                            .onTapGesture {
                                viewModel.selectSearchResult(result)
                                viewModel.viewMode = .browse
                            }
                    }
                }
                .padding(20)
            }
        }
    }
}

// MARK: - Search Result Card

struct SearchResultCard: View {
    let result: MemorySearchResult
    let query: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // File header
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.accentColor)
                
                Text(result.filename)
                    .font(.ClawK.bodyBold)
                    .lineLimit(1)
                
                Spacer()
                
                // Score badge
                ScoreBadge(score: result.score)
            }
            
            // Path
            Text(result.path)
                .font(.ClawK.caption)
                .foregroundColor(.secondary)
            
            // Snippet with highlighting
            HighlightedText(text: result.snippet, highlight: query)
                .font(.system(.body, design: .monospaced))
                .lineLimit(4)
            
            // Line info
            if result.startLine > 0 {
                Text("Lines \(result.startLine)-\(result.endLine)")
                    .font(.ClawK.captionSmall)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        .contentShape(Rectangle())
    }
}

// MARK: - Score Badge

struct ScoreBadge: View {
    let score: Double
    
    var color: Color {
        if score >= 0.9 { return .green }
        if score >= 0.7 { return .orange }
        return .gray
    }
    
    var body: some View {
        Text(String(format: "%.0f%%", score * 100))
            .font(.ClawK.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(6)
    }
}

// MARK: - Highlighted Text

struct HighlightedText: View {
    let text: String
    let highlight: String
    
    var body: some View {
        if highlight.isEmpty {
            Text(text)
        } else {
            attributedText
        }
    }
    
    var attributedText: Text {
        let lowercaseText = text.lowercased()
        let lowercaseHighlight = highlight.lowercased()
        
        var result = Text("")
        var currentIndex = text.startIndex
        
        while let range = lowercaseText.range(of: lowercaseHighlight, range: currentIndex..<text.endIndex) {
            // Add text before match
            let beforeRange = currentIndex..<range.lowerBound
            if !beforeRange.isEmpty {
                result = result + Text(text[beforeRange])
            }
            
            // Add highlighted match (using original case)
            let matchedText = text[range]
            result = result + Text(matchedText)
                .foregroundColor(.yellow)
                .bold()
            
            currentIndex = range.upperBound
        }
        
        // Add remaining text
        if currentIndex < text.endIndex {
            result = result + Text(text[currentIndex...])
        }
        
        return result
    }
}
