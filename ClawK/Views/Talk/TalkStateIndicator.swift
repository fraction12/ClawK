//
//  TalkStateIndicator.swift
//  ClawK
//
//  Animated state indicators for Talk Mode
//

import SwiftUI

struct TalkStateIndicator: View {
    let state: TalkConversationState
    let audioLevels: [Float]

    @State private var animationPhase: CGFloat = 0
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            switch state {
            case .idle:
                IdleIndicator()
            case .listening:
                ListeningIndicator(audioLevels: audioLevels)
            case .thinking:
                ThinkingIndicator(animationPhase: animationPhase)
            case .speaking:
                SpeakingIndicator(animationPhase: animationPhase)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(
                .linear(duration: DSAnimation.Duration.verySlow * 2)
                    .repeatForever(autoreverses: false)
            ) {
                animationPhase = 1
            }
        }
    }
}

// MARK: - Idle

private struct IdleIndicator: View {
    @State private var breathing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.Semantic.info.opacity(Color.Opacity.light))
                .frame(width: 80, height: 80)
                .scaleEffect(breathing ? 1.05 : 0.95)

            Circle()
                .fill(Color.Semantic.info.opacity(Color.Opacity.normal))
                .frame(width: 60, height: 60)

            Image(systemName: "mic.fill")
                .font(.title)
                .foregroundColor(Color.Semantic.info)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: DSAnimation.Duration.verySlow * 2)
                    .repeatForever(autoreverses: true)
            ) {
                breathing = true
            }
        }
    }
}

// MARK: - Listening

private struct ListeningIndicator: View {
    let audioLevels: [Float]

    var body: some View {
        ZStack {
            // Glow based on audio level
            let recentLevels = audioLevels.suffix(8)
            let avgLevel = recentLevels.reduce(0, +) / max(Float(recentLevels.count), 1)

            Circle()
                .fill(Color.Semantic.success.opacity(Double(avgLevel) * 3))
                .frame(width: 100, height: 100)
                .blur(radius: 20)

            // Waveform bars
            HStack(spacing: 3) {
                ForEach(0..<24, id: \.self) { i in
                    let level = i < audioLevels.count ? audioLevels[i] : Float(0)
                    let normalizedHeight = max(CGFloat(level) * 300, 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.Semantic.success)
                        .frame(width: 4, height: min(normalizedHeight, 60))
                        .animation(
                            .interpolatingSpring(stiffness: 300, damping: 15),
                            value: level
                        )
                }
            }
            .frame(height: 60)
        }
    }
}

// MARK: - Thinking

private struct ThinkingIndicator: View {
    let animationPhase: CGFloat
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // Rotating gradient ring
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.Semantic.warning,
                            .orange,
                            Color.Semantic.warning.opacity(Color.Opacity.strong),
                            Color.Semantic.warning,
                        ],
                        center: .center
                    ),
                    lineWidth: 4
                )
                .frame(width: 70, height: 70)
                .rotationEffect(.degrees(rotation))

            // Pulsing core
            Circle()
                .fill(Color.Semantic.warning.opacity(Color.Opacity.normal))
                .frame(width: 50, height: 50)
                .scaleEffect(1.0 + animationPhase * 0.15)

            Image(systemName: "brain")
                .font(.title2)
                .foregroundColor(Color.Semantic.warning)
                .symbolEffect(.pulse)
        }
        .onAppear {
            withAnimation(
                .linear(duration: DSAnimation.Duration.verySlow * 2)
                    .repeatForever(autoreverses: false)
            ) {
                rotation = 360
            }
        }
    }
}

// MARK: - Speaking

private struct SpeakingIndicator: View {
    let animationPhase: CGFloat
    @State private var ringScale1: CGFloat = 0.8
    @State private var ringScale2: CGFloat = 0.6
    @State private var ringScale3: CGFloat = 0.4

    var body: some View {
        ZStack {
            // Sound wave rings
            Circle()
                .stroke(
                    Color.Semantic.success.opacity(Color.Opacity.normal),
                    lineWidth: 2
                )
                .frame(width: 90, height: 90)
                .scaleEffect(ringScale1)

            Circle()
                .stroke(
                    Color.Semantic.success.opacity(Color.Opacity.strong),
                    lineWidth: 2
                )
                .frame(width: 70, height: 70)
                .scaleEffect(ringScale2)

            Circle()
                .stroke(
                    Color.Semantic.success.opacity(Color.Opacity.heavy),
                    lineWidth: 2
                )
                .frame(width: 50, height: 50)
                .scaleEffect(ringScale3)

            Image(systemName: "speaker.wave.3.fill")
                .font(.title2)
                .foregroundColor(Color.Semantic.success)
                .symbolEffect(.variableColor.iterative)
        }
        .onAppear {
            withAnimation(
                .easeOut(duration: 1.5)
                    .repeatForever(autoreverses: true)
            ) {
                ringScale1 = 1.2
                ringScale2 = 1.1
                ringScale3 = 1.0
            }
        }
    }
}
