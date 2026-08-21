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
                    Text("Your Playlists")
                        .font(.system(size: 28, weight: .bold))
                    Spacer()
                    Button(action: {
                        createNewPlaylist()
                    }) {
                        Label("New Playlist", systemImage: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                    .aspectRatio(1, contentMode: .fill)
                    .cornerRadius(12)
                
                if let path = playlist.firstArtworkCachePath, let nsImage = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.5))
                }
            }
            .shadow(color: Color.black.opacity(isHovered ? 0.3 : 0.1), radius: isHovered ? 12 : 8, y: 4)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(playlist.trackCount) track\(playlist.trackCount == 1 ? "" : "s")")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
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
                Rectangle()
                    .fill(color.opacity(0.15))
                    .aspectRatio(1, contentMode: .fill)
                    .cornerRadius(12)
                
                Image(systemName: systemImage)
                    .font(.system(size: 48))
                    .foregroundColor(color)
                    .shadow(color: color.opacity(0.5), radius: 8, x: 0, y: 4)
            }
            .shadow(color: Color.black.opacity(isHovered ? 0.3 : 0.1), radius: isHovered ? 12 : 8, y: 4)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("Smart Playlist")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
