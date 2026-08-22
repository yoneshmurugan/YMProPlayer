// SearchView.swift
// ytsplayer

import SwiftUI

struct SearchView: View {
    @ObservedObject var searchVM: SearchViewModel
    @ObservedObject var playbackVM: PlaybackViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search tracks…", text: $searchVM.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                if !searchVM.query.isEmpty {
                    Button(action: { searchVM.query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                if searchVM.isSearching {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(10)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.top, 24)
            
            // Filter Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(SearchFilter.allCases, id: \.self) { filter in
                        Button(action: {
                            searchVM.selectedFilter = filter
                        }) {
                            Text(filter.rawValue)
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(searchVM.selectedFilter == filter ? Color.purple : Color.white.opacity(0.1))
                                .foregroundStyle(searchVM.selectedFilter == filter ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            Divider()

            if searchVM.hasNoResults {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "music.note.list")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("No results for '\(searchVM.query)'")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List {
                    if (!searchVM.artistResults.isEmpty && (searchVM.selectedFilter == .all || searchVM.selectedFilter == .artist)) {
                        Section(header: Text("Artists").font(.system(size: 14, weight: .bold)).foregroundStyle(.primary)) {
                            ForEach(searchVM.artistResults) { artist in
                                HStack(spacing: 12) {
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(.purple)
                                    VStack(alignment: .leading) {
                                        Text(artist.name).font(.system(size: 13, weight: .medium))
                                        Text("\(artist.albumCount) albums").font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    
                    if (!searchVM.albumResults.isEmpty && (searchVM.selectedFilter == .all || searchVM.selectedFilter == .album)) {
                        Section(header: Text("Albums").font(.system(size: 14, weight: .bold)).foregroundStyle(.primary)) {
                            ForEach(searchVM.albumResults) { album in
                                HStack(spacing: 12) {
                                    Image(systemName: "square.stack.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(.orange)
                                    VStack(alignment: .leading) {
                                        Text(album.title).font(.system(size: 13, weight: .medium))
                                        Text(album.artistName ?? "Unknown").font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    
                    if (!searchVM.playlistResults.isEmpty && (searchVM.selectedFilter == .all || searchVM.selectedFilter == .playlist)) {
                        Section(header: Text("Playlists").font(.system(size: 14, weight: .bold)).foregroundStyle(.primary)) {
                            ForEach(searchVM.playlistResults) { playlist in
                                HStack(spacing: 12) {
                                    Image(systemName: "music.note.list")
                                        .font(.system(size: 24))
                                        .foregroundStyle(.blue)
                                    Text(playlist.name).font(.system(size: 13, weight: .medium))
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    
                    if (!searchVM.results.isEmpty && (searchVM.selectedFilter == .all || searchVM.selectedFilter == .songs)) {
                        Section(header: Text("Songs").font(.system(size: 14, weight: .bold)).foregroundStyle(.primary)) {
                            ForEach(Array(searchVM.results.enumerated()), id: \.element.id) { index, track in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(track.title)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(
                                                playbackVM.currentTrack?.id == track.id ? Color.purple : .primary
                                            )
                                            .lineLimit(1)
                                        HStack(spacing: 4) {
                                            if let artist = track.artistName {
                                                Text(artist)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.secondary)
                                            }
                                            if let album = track.albumTitle {
                                                Text("·")
                                                    .foregroundStyle(.tertiary)
                                                Text(album)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.tertiary)
                                            }
                                        }
                                        .lineLimit(1)
                                    }

                                    Spacer()

                                    Text(formatDuration(track.duration))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    playbackVM.play(
                                        track: track,
                                        queue: searchVM.results,
                                        startIndex: index
                                    )
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func formatDuration(_ sec: Double) -> String {
        let t = Int(sec)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
