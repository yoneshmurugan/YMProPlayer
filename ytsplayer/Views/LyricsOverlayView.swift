import SwiftUI
import GRDB

struct LyricsOverlayView: View {
    @EnvironmentObject var playbackVM: PlaybackViewModel
    @State private var lyrics: String?
    @State private var isLoading = false
    let database: DatabasePool
    
    // LRC parser helper
    struct LyricLine: Identifiable {
        let id = UUID()
        let time: Double?
        let text: String
    }
    
    var parsedLyrics: [LyricLine] {
        guard let text = lyrics else { return [] }
        return text.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return nil }
            // Try parsing LRC timestamp [mm:ss.xx]
            if trimmed.hasPrefix("[") && trimmed.count > 10 {
                let timeString = trimmed.dropFirst().prefix(8)
                let textPart = trimmed.dropFirst(10)
                let parts = timeString.components(separatedBy: ":")
                if parts.count == 2, let min = Double(parts[0]), let sec = Double(parts[1]) {
                    return LyricLine(time: min * 60 + sec, text: String(textPart))
                }
            }
            return LyricLine(time: nil, text: trimmed)
        }
    }
    
    var currentLineIndex: Int? {
        let currentProgress = playbackVM.playbackProgress * (playbackVM.currentTrack?.duration ?? 0)
        let lines = parsedLyrics
        guard !lines.isEmpty, lines[0].time != nil else { return nil } // Only sync if we have timestamps
        
        var lastValidIndex: Int = 0
        for (i, line) in lines.enumerated() {
            if let t = line.time {
                if currentProgress >= t {
                    lastValidIndex = i
                } else {
                    break
                }
            }
        }
        return lastValidIndex
    }
    
    var body: some View {
        ZStack {
            // Transparent background (parent has the full blur)
            Color.black.opacity(0.4)
            
            if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            } else if parsedLyrics.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.mic")
                        .font(.system(size: 48))
                        .foregroundColor(.white.opacity(0.5))
                    Text("No Lyrics Found")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    Button("Fetch Online") {
                        Task { await fetchLyrics() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 24) {
                            ForEach(Array(parsedLyrics.enumerated()), id: \.element.id) { index, line in
                                let isCurrent = index == currentLineIndex
                                let isPast = currentLineIndex != nil && index < currentLineIndex!
                                
                                Text(line.text)
                                    .font(.system(size: isCurrent ? 36 : 28, weight: isCurrent ? .bold : .semibold))
                                    .foregroundColor(isCurrent ? .white : .white.opacity(isPast ? 0.3 : 0.6))
                                    .multilineTextAlignment(.center)
                                    .scaleEffect(isCurrent ? 1.05 : 1.0)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCurrent)
                                    .id(index)
                            }
                        }
                        .padding(.vertical, 300)
                        .padding(.horizontal, 40)
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: currentLineIndex) { newIndex in
                        if let index = newIndex {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                proxy.scrollTo(index, anchor: .center)
                            }
                        }
                    }
                }
                // Fade out edges
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.2),
                            .init(color: .black, location: 0.8),
                            .init(color: .clear, location: 1)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .onAppear { loadInitialLyrics() }
        .onChange(of: playbackVM.currentTrack?.id) { _ in loadInitialLyrics() }
    }
    
    private func loadInitialLyrics() {
        guard let track = playbackVM.currentTrack else {
            lyrics = nil
            return
        }
        if let l = track.lyrics, !l.isEmpty {
            lyrics = l
        } else {
            lyrics = nil
        }
    }
    
    private func fetchLyrics() async {
        guard let track = playbackVM.currentTrack else { return }
        isLoading = true
        do {
            let fetched = try await LyricsService.shared.fetchAndEmbedLyrics(for: track, database: database)
            await MainActor.run {
                self.lyrics = fetched
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
            print("Lyrics fetch failed: \(error)")
        }
    }
}
