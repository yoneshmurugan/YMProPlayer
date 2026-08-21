// LibraryView.swift
// ytsplayer

import SwiftUI

struct LibraryView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playbackVM: PlaybackViewModel
    @State private var selectedAlbum: AlbumViewModel?
    @State private var showFolderPicker = false
    @AppStorage("albumsIsGridView") private var isGridView = true
    var onProfileTapped: (() -> Void)? = nil

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {

            // ── Custom Toolbar ───────────────────────────────────────────
            HStack {
                // View Toggles (Grid / Dice)
                HStack(spacing: 0) {
                    Button(action: { withAnimation { isGridView = true } }) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 14))
                            .frame(width: 32, height: 26)
                            .background(isGridView ? Color.white.opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { withAnimation { isGridView = false } }) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 14))
                            .frame(width: 32, height: 26)
                            .background(!isGridView ? Color.white.opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(4)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.white.opacity(0.8))
                
                Spacer()
                
                HStack(spacing: 24) {
                    // Sort Dropdown
                    Menu {
                        ForEach(LibraryViewModel.SortOrder.allCases, id: \.self) { order in
                            Button(action: { libraryVM.sortOrder = order }) {
                                if libraryVM.sortOrder == order {
                                    Label(order.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(order.rawValue)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(libraryVM.sortOrder.rawValue)
                                .font(.system(size: 13, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(.white.opacity(0.9))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    
                    // Search Icon
                    Button(action: {}) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    
                    // Avatar
                    Button(action: { onProfileTapped?() }) {
                        Circle()
                            .fill(LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 28, height: 28)
                            .overlay(Text("Y").font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)

            // ── Scan Progress Bar ──────────────────────────────────────────
            if libraryVM.isScanning {
                VStack(spacing: 4) {
                    ProgressView(value: libraryVM.scanProgress)
                        .progressViewStyle(.linear)
                        .tint(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                    Text("Scanning \(libraryVM.scanner.scannedCount) / \(libraryVM.scanner.totalCount) tracks…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            if libraryVM.albums.isEmpty && !libraryVM.isScanning {
                // ── Empty State ────────────────────────────────────────────
                emptyState
            } else {
                // ── Album Grid or List ─────────────────────────────────────
                ScrollView {
                    if isGridView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(libraryVM.albums) { album in
                                AlbumCard(
                                    album: album,
                                    isSelected: selectedAlbum?.id == album.id
                                )
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedAlbum = album
                                    }
                                }
                            }
                        }
                        .padding(16)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(libraryVM.albums) { album in
                                AlbumListRow(
                                    album: album,
                                    isSelected: selectedAlbum?.id == album.id
                                )
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedAlbum = album
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .sheet(item: $selectedAlbum) { album in
            AlbumDetailView(
                album: album,
                tracks: libraryVM.fetchTracks(for: album),
                playbackVM: playbackVM
            )
        }
        .onChange(of: libraryVM.sortOrder) { _ in
            libraryVM.loadAlbums()
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                _ = url.startAccessingSecurityScopedResource()
                libraryVM.addFolder(url: url)
                libraryVM.startScan()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "music.note.house")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple.opacity(0.6), .blue.opacity(0.6)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            Text("No Music Library")
                .font(.system(size: 22, weight: .semibold))
            Text("Click the folder icon in the toolbar to select\nyour FLAC music directory.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Select Music Folder") { showFolderPicker = true }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Album Card

struct AlbumCard: View {
    let album: AlbumViewModel
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Artwork
            artworkImage
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if album.isHiRes {
                        if let nsImage = NSImage(named: "hires.png") {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 18)
                                .padding(10)
                                .shadow(color: .black.opacity(0.8), radius: 6, y: 2)
                        }
                    }
                }
                .shadow(
                    color: .black.opacity(isHovered ? 0.6 : 0.25),
                    radius: isHovered ? 16 : 8,
                    y: isHovered ? 8 : 4
                )
                .scaleEffect(isHovered ? 1.04 : 1.0)
                .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isHovered)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.purple.opacity(isSelected ? 0.8 : 0), .blue.opacity(isSelected ? 0.8 : 0)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 3 : 0
                        )
                )

            // Text
            VStack(alignment: .leading, spacing: 3) {
                Text(album.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let artist = album.artistName {
                    Text(artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                if let year = album.year {
                    Text(String(year))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 4)
        }
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var artworkImage: some View {
        if let path = album.artworkCachePath,
           let cacheDir = ImageDownsampler.artworkCacheDirectory() {
            let url = cacheDir.appendingPathComponent(path)
            AsyncImage(url: url) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                placeholderArt
            }
        } else {
            placeholderArt
        }
    }

    private var placeholderArt: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(hue: Double(album.id % 10) / 10.0, saturation: 0.45, brightness: 0.25),
                        Color(hue: Double((album.id + 3) % 10) / 10.0, saturation: 0.35, brightness: 0.18)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.2))
            )
    }
}

// MARK: - Album List Row

struct AlbumListRow: View {
    let album: AlbumViewModel
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 16) {
            // Artwork
            artworkImage
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(album.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    if let artist = album.artistName {
                        Text(artist)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    if let year = album.year {
                        Text("•")
                            .foregroundStyle(.white.opacity(0.4))
                        Text(String(year))
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }

            Spacer()

            // HiRes Badge
            if album.isHiRes {
                if let nsImage = NSImage(named: "hires.png") {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 16)
                        .opacity(0.9)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.08 : (isSelected ? 0.05 : 0.02)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.purple.opacity(isSelected ? 0.8 : 0), .blue.opacity(isSelected ? 0.8 : 0)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: isSelected ? 2 : 0
                )
        )
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var artworkImage: some View {
        if let path = album.artworkCachePath,
           let cacheDir = ImageDownsampler.artworkCacheDirectory() {
            let url = cacheDir.appendingPathComponent(path)
            AsyncImage(url: url) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                placeholderArt
            }
        } else {
            placeholderArt
        }
    }

    private var placeholderArt: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(hue: Double(album.id % 10) / 10.0, saturation: 0.45, brightness: 0.25),
                        Color(hue: Double((album.id + 3) % 10) / 10.0, saturation: 0.35, brightness: 0.18)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.2))
            )
    }
}
