// DetailContentView.swift
// ytsplayer
//
// CRITICAL ARCHITECTURE NOTE (macOS 27 constraint loop fix):
//
// ContentView previously held `@ObservedObject var playbackVM` AND rendered the
// NowPlayingBar + inspector together. Every time `playbackProgress` ticked (every
// ~0.25s from the playback timer), SwiftUI re-evaluated ContentView.body. This
// caused the `.inspector` hosting view (_NSConstraintBasedLayoutHostingView) to
// cancel its async render and demand a new constraint pass, which in turn triggered
// another render cancellation — an infinite loop that crashed with NSGenericException
// ("Update Constraints in Window passes exceeded view count").
//
// The fix: move everything that needs @ObservedObject playbackVM into THIS view.
// ContentView now only renders the NavigationSplitView shell and static chrome.
// When the timer ticks, only DetailContentView re-evaluates — the inspector host
// is a stable child of THIS view, not ContentView, so constraint churn stops.

import SwiftUI
import GRDB

class HeroState: ObservableObject {
    @Published var selectedAlbum: AlbumViewModel? = nil
}

struct HeroNamespaceKey: EnvironmentKey {
    static var defaultValue: Namespace.ID = Namespace().wrappedValue
}

extension EnvironmentValues {
    var heroNamespace: Namespace.ID {
        get { self[HeroNamespaceKey.self] }
        set { self[HeroNamespaceKey.self] = newValue }
    }
}

struct DetailContentView: View {
    @Binding var selectedTab: AppTab?
    @Binding var showFullScreenPlayer: Bool
    @Binding var showSettings: Bool
    @Binding var showInspector: Bool

    let playbackVM: PlaybackViewModel
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var searchVM: SearchViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var playlistManager: PlaylistManager

    let db: DatabasePool
    
    @Namespace private var heroNamespace
    @StateObject private var heroState = HeroState()

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .bottom) {
            // ── Tab Content ─────────────────────────────────────────────────
            Group {
                switch selectedTab {
                case .home, nil:
                    HomeView(
                        libraryVM: libraryVM,
                        playbackVM: playbackVM,
                        onSearchTapped: { selectedTab = .search },
                        onProfileTapped: { showSettings = true },
                        onNavigateToTab: { tab in selectedTab = tab }
                    )
                case .albums:
                    LibraryView(libraryVM: libraryVM, playbackVM: playbackVM, onSearchTapped: { selectedTab = .search })
                case .artists:
                    ArtistsView(libraryVM: libraryVM, playbackVM: playbackVM, onSearchTapped: { selectedTab = .search })
                case .tracks:
                    TracksView(libraryVM: libraryVM, playbackVM: playbackVM, onSearchTapped: { selectedTab = .search })
                case .hierarchy:
                    HierarchyView(libraryVM: libraryVM, playbackVM: playbackVM, onSearchTapped: { selectedTab = .search })
                case .playlists:
                    PlaylistsView()
                case .playlist(let id):
                    PlaylistEditorView(playlistId: id, db: db)
                        .environmentObject(playbackVM)
                        .id(id)
                case .search:
                    SearchView(searchVM: searchVM, libraryVM: libraryVM, playbackVM: playbackVM)
                case .mock(let title):
                    mockView(title)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(themeManager.glassIntensity.material)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 120)
            }

            // ── Now Playing Bar (Floating) ──────────────────────────────────
            NowPlayingBar(
                vm: playbackVM,
                onArtworkTap: {
                    if playbackVM.currentTrack != nil {
                        showFullScreenPlayer = true
                    }
                }
            )
            } // Close ZStack
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // ── Hero Overlay ──
            if let heroAlbum = heroState.selectedAlbum {
                AlbumDetailView(
                    album: heroAlbum,
                    tracks: libraryVM.fetchTracks(for: heroAlbum),
                    playbackVM: playbackVM,
                    onClose: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            heroState.selectedAlbum = nil
                        }
                    }
                )
                .layoutPriority(1)
                .background(themeManager.glassIntensity.material) // Strong background behind the hero
                .transition(.move(edge: .trailing).combined(with: .opacity)) // Slide in from trailing
                .zIndex(100)
            }

            if showInspector {
                Divider()
                NowPlayingInspectorView(vm: playbackVM) {
                    if playbackVM.currentTrack != nil {
                        showFullScreenPlayer = true
                    }
                }
                .frame(width: 280)
                .layoutPriority(1)
                .background(themeManager.glassIntensity.material) // Match standard sidebar feel
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: showInspector)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        showInspector.toggle()
                    }
                }) {
                    Image(systemName: "sidebar.right")
                        .foregroundStyle(showInspector ? Color.accentColor : Color.primary)
                }
                .help("Toggle Now Playing Inspector")
            }
        }
        .frame(minWidth: 300, minHeight: 300)
        .background(NowPlayingTouchBar(playbackVM: playbackVM))
        .environment(\.heroNamespace, heroNamespace)
        .environmentObject(heroState)
    }

    private func mockView(_ title: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 48))
                .foregroundStyle(.purple)
            Text("\(title) is coming soon")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NowPlayingTouchBar: View {
    @ObservedObject var playbackVM: PlaybackViewModel
    
    var body: some View {
        Color.clear
            .touchBar {
                // Premium Static Icon (Replaces buggy NSImage)
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                
                // Static Track Info (Expanded width + Audiophile Stats)
                if let track = playbackVM.currentTrack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(1)
                        
                        let stats = "\(playbackVM.currentBitDepth)-bit / \(playbackVM.currentSampleRate / 1000)kHz"
                        Text("\(track.artistName ?? "Unknown") • \(stats)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 300, alignment: .leading)
                    .clipped()
                } else {
                    Text("YM Pro")
                        .font(.system(size: 15, weight: .bold))
                }
                
                // Format Badge, Hi-Res Logo
                if let track = playbackVM.currentTrack {
                    if playbackVM.currentBitDepth >= 24, let nsImage = NSImage(named: "hires.png") {
                        let _ = { nsImage.isTemplate = false }()
                        Image(nsImage: nsImage)
                            .resizable()
                            .renderingMode(.original)
                            .scaledToFit()
                            .frame(height: 14)
                    }
                }
                
                Spacer(minLength: 16)
                
                Text("\(playbackVM.currentTimeString) / \(playbackVM.totalTimeString)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 75)
                    .layoutPriority(1)
                
                // Volume Slider (Disabled if Bit-Perfect)
                Slider(value: $playbackVM.volume, in: 0...1) {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .frame(width: 150)
                .tint(playbackVM.isBitPerfect ? .gray : .purple)
                .grayscale(playbackVM.isBitPerfect ? 1.0 : 0.0)
                .disabled(playbackVM.isBitPerfect)
            }
    }
}
