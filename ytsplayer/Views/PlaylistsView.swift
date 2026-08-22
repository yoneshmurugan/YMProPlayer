import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject var playlistManager: PlaylistManager
    @Environment(\.openWindow) var openWindow
    
    // Grid layout: adaptive columns, minimum width 160
    let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Playlists")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.white, .gray], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    Spacer()
                    Button(action: {
                        createNewPlaylist()
                    }) {
                        Label("New Playlist", systemImage: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.purple))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .shadow(color: .purple.opacity(0.3), radius: 8, y: 4)
                }
                
                // Smart Playlists Section
                LazyVGrid(columns: columns, spacing: 24) {
                    SmartPlaylistCard(title: "Favorites", systemImage: "heart.fill", color: .red)
                        .onTapGesture { openWindow(id: "PlaylistEditor", value: Int64(-1)) }
                    SmartPlaylistCard(title: "Top 50 Heavy Rotation", systemImage: "flame.fill", color: .orange)
                        .onTapGesture { openWindow(id: "PlaylistEditor", value: Int64(-2)) }
                    SmartPlaylistCard(title: "Hi-Res Audio", systemImage: "waveform", color: .purple)
                        .onTapGesture { openWindow(id: "PlaylistEditor", value: Int64(-3)) }
                }
                
                Divider().padding(.vertical, 16)
                
                if playlistManager.playlists.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No playlists yet")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(playlistManager.playlists) { playlist in
                            PlaylistCard(playlist: playlist)
                                .onTapGesture {
                                    openWindow(id: "PlaylistEditor", value: playlist.id)
                                }
                                .contextMenu {
                                    Button("Open in New Window") {
                                        openWindow(id: "PlaylistEditor", value: playlist.id)
                                    }
                                    Button("Delete Playlist", role: .destructive) {
                                        playlistManager.deletePlaylist(id: playlist.id)
                                    }
                                }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    private func createNewPlaylist() {
        let name = "New Playlist"
        if let id = playlistManager.createPlaylist(name: name) {
            openWindow(id: "PlaylistEditor", value: id)
        }
    }
}

struct PlaylistCard: View {
    let playlist: PlaylistViewModel
    @State private var isHovered = false
    
    private func formatTotalDuration(_ duration: Double) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .aspectRatio(1, contentMode: .fill)
                
                if let path = playlist.firstArtworkCachePath, let nsImage = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.3))
                }
                
                if isHovered {
                    Rectangle()
                        .fill(Color.black.opacity(0.4))
                        .transition(.opacity)
                    
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.white)
                        .shadow(radius: 10)
                        .scaleEffect(isHovered ? 1.0 : 0.8)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(isHovered ? 0.5 : 0.2), radius: isHovered ? 12 : 8, y: isHovered ? 8 : 4)
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .animation(.easeOut(duration: 0.2), value: isHovered)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("\(playlist.trackCount) tracks • \(formatTotalDuration(playlist.totalDuration))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 4)
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct SmartPlaylistCard: View {
    let title: String
    let systemImage: String
    let color: Color
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                LinearGradient(colors: [color.opacity(0.6), color.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .aspectRatio(1, contentMode: .fill)
                
                Image(systemName: systemImage)
                    .font(.system(size: 48))
                    .foregroundColor(color)
                    .shadow(color: color.opacity(0.5), radius: 10, y: 5)
                
                if isHovered {
                    Rectangle()
                        .fill(Color.black.opacity(0.2))
                        .transition(.opacity)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.white)
                        .shadow(radius: 10)
                        .scaleEffect(isHovered ? 1.0 : 0.8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: color.opacity(isHovered ? 0.4 : 0.15), radius: isHovered ? 12 : 8, y: isHovered ? 8 : 4)
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .animation(.easeOut(duration: 0.2), value: isHovered)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("Smart Playlist")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 4)
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
