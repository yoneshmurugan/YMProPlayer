// LibraryView.swift
// ytsplayer

import SwiftUI

struct LibraryView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playbackVM: PlaybackViewModel
    @State private var selectedAlbum: AlbumViewModel?
    @State private var showFolderPicker = false
    var onProfileTapped: (() -> Void)? = nil

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {

            // ── Top Header: Library > Albums ───────────────────────────────
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text("Library")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Albums")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
                
                Spacer()
                
                // Search pill
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.white.opacity(0.5))
                        .font(.system(size: 13))
                    Text("Search Music, Playlists, Artists…")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(width: 280)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                
                Spacer().frame(width: 16)
                
                // Avatar
                Button(action: { onProfileTapped?() }) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.purple, .indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text("Y")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.15))

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
                // ── Album Grid ─────────────────────────────────────────────
                ScrollView {
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort By", selection: $libraryVM.sortOrder) {
                        ForEach(LibraryViewModel.SortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button(action: { showFolderPicker = true }) {
                    Label("Add Library", systemImage: "folder.badge.plus")
                }
                .help("Select your music folder to scan for FLAC files")
            }
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                _ = url.startAccessingSecurityScopedResource()
                libraryVM.startScan(rootURL: url)
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
