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

            if searchVM.results.isEmpty && !searchVM.query.isEmpty && !searchVM.isSearching {
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
                List(Array(searchVM.results.enumerated()), id: \.element.id) { index, track in
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
                .listStyle(.plain)
            }
        }
    }

    private func formatDuration(_ sec: Double) -> String {
        let t = Int(sec)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
