// LibraryView.swift
// ytsplayer

import SwiftUI

struct LibraryView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playbackVM: PlaybackViewModel
    @State private var selectedAlbum: AlbumViewModel?
    @State private var showFolderPicker = false

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {

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
        VStack(alignment: .leading, spacing: 8) {
            // Artwork
            artworkImage
                .frame(width: .infinity, height: nil)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(
                    color: .black.opacity(isHovered ? 0.4 : 0.2),
                    radius: isHovered ? 12 : 6
                )
                .scaleEffect(isHovered ? 1.03 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isHovered)

            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if let artist = album.artistName {
                    Text(artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let year = album.year {
                    Text(String(year))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .onHover { isHovered = $0 }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.purple.opacity(isSelected ? 0.7 : 0), lineWidth: 2)
        )
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
