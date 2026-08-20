// HierarchyView.swift
// ytsplayer

import SwiftUI

struct HierarchyView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playbackVM: PlaybackViewModel
    
    @State private var rootNodes: [FolderNode] = []
    @State private var isScanning = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Library")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.5))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
                Text("Hierarchy")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            
            Divider().background(Color.white.opacity(0.1))
            
            if isScanning {
                VStack {
                    Spacer()
                    ProgressView("Scanning Disk...")
                        .tint(.purple)
                    Spacer()
                }
            } else if rootNodes.isEmpty {
                VStack {
                    Spacer()
                    Text("No FLAC files found or library folder not set.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List(rootNodes, children: \.children) { node in
                    if node.isDirectory {
                        Label(node.name, systemImage: "folder.fill")
                            .foregroundStyle(.blue)
                    } else {
                        Button(action: {
                            playTrack(at: node.url)
                        }) {
                            Label(node.name, systemImage: "music.note")
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .onAppear {
            scan()
        }
        .onChange(of: libraryVM.libraryRootURL) { _ in
            scan()
        }
    }
    
    private func scan() {
        guard let url = libraryVM.libraryRootURL else { return }
        isScanning = true
        // Move expensive file IO to background
        Task.detached(priority: .userInitiated) {
            let nodes = FolderNode.scanDirectory(at: url)
            await MainActor.run {
                self.rootNodes = nodes
                self.isScanning = false
            }
        }
    }
    
    private func playTrack(at url: URL) {
        if let track = libraryVM.fetchTrack(byPath: url.path) {
            // Found in DB
            playbackVM.play(track: track, queue: [track], startIndex: 0)
        } else {
            // Fallback for unscanned files
            let track = TrackViewModel(
                id: Int64(url.hashValue), // Fake ID
                filePath: url.path,
                title: url.deletingPathExtension().lastPathComponent,
                trackNumber: nil,
                duration: 0,
                sampleRate: 0,
                bitDepth: 0,
                artistName: "Unknown Artist",
                albumTitle: "Unknown Album",
                albumArtworkPath: nil,
                lyrics: nil
            )
            playbackVM.play(track: track, queue: [track], startIndex: 0)
        }
    }
}
