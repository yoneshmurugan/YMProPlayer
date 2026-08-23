// IntroVideoView.swift
// ytsplayer
//
// Seamless intro video splash screen.

import SwiftUI
import AVFoundation
import AVKit

struct IntroVideoView: View {
    @Binding var isFinished: Bool

    @State private var player: AVPlayer? = nil
    @State private var opacity: Double = 1.0
    @State private var hasFinished = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = player {
                // Use a wrapper around AVPlayerView to completely hide all controls.
                SeamlessVideoPlayerView(player: player)
                    .ignoresSafeArea()
            }

            // Invisible button over the whole screen to allow click-to-skip
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { finishIntro() }
                
            // Subtle Skip button
            VStack {
                HStack {
                    Spacer()
                    Button(action: { finishIntro() }) {
                        Text("Skip ▹")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.6))
                            .padding(8)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .padding(20)
                }
                Spacer()
            }
        }
        .opacity(opacity)
        .onAppear {
            setupAndPlay()
        }
        .ignoresSafeArea()
    }

    private func setupAndPlay() {
        let videoName = "intro_video"
        var videoURL = Bundle.main.url(forResource: videoName, withExtension: "mp4")

        // Fallback for local debugging
        if videoURL == nil {
            let path = "/Users/yonesh/Projects/Player/ytsplayer/Assets/\(videoName).mp4"
            if FileManager.default.fileExists(atPath: path) {
                videoURL = URL(fileURLWithPath: path)
            }
        }

        guard let url = videoURL else {
            finishIntro()
            return
        }

        let avPlayer = AVPlayer(url: url)
        // Mute the video to prevent conflict with our CoreAudio HAL engine!
        avPlayer.isMuted = true
        avPlayer.actionAtItemEnd = .none
        self.player = avPlayer

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: avPlayer.currentItem,
            queue: .main
        ) { _ in finishIntro() }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: avPlayer.currentItem,
            queue: .main
        ) { _ in finishIntro() }

        // Max duration 10.5s fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.5) {
            finishIntro()
        }

        avPlayer.play()
    }

    private func finishIntro() {
        guard !hasFinished else { return }
        hasFinished = true
        player?.pause()
        
        withAnimation(.easeOut(duration: 0.5)) { opacity = 0.0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isFinished = true
        }
    }
}

// Seamless AppKit video player that hides all controls natively
struct SeamlessVideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none // Hides all player controls completely!
        view.videoGravity = .resizeAspectFill
        view.showsFullScreenToggleButton = false
        view.showsSharingServiceButton = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

