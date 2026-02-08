//
//  TalkWaveformView.swift
//  ClawK
//
//  Audio waveform visualization for Talk Mode
//

import SwiftUI

struct TalkWaveformView: View {
    let levels: [Float]
    var color: Color = Color.Semantic.success
    var barCount: Int = 32
    var barSpacing: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    let level = i < levels.count ? levels[i] : Float(0)
                    let normalizedHeight = max(
                        CGFloat(level) * geometry.size.height * 4,
                        2
                    )
                    let barWidth = max(
                        (geometry.size.width - barSpacing * CGFloat(barCount - 1))
                            / CGFloat(barCount),
                        2
                    )

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color.opacity(0.6 + Double(level) * 2))
                        .frame(
                            width: barWidth,
                            height: min(normalizedHeight, geometry.size.height)
                        )
                        .animation(
                            .interpolatingSpring(stiffness: 300, damping: 15),
                            value: level
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}
