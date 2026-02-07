//
//  DSRefreshButton.swift
//  ClawK
//
//  Refresh button with spinning animation
//

import SwiftUI

struct DSRefreshButton: View {
    let action: () -> Void
    var isRefreshing: Bool = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
        }
        .disabled(isRefreshing)
        .help("Refresh")
    }
}
