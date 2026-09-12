import SwiftUI
import GRDB
import UniformTypeIdentifiers

struct LyricsOverlayView: View {
    @EnvironmentObject var playbackVM: PlaybackViewModel
    @State private var lyrics: String?
    @State private var cachedParsedLyrics: [LyricLine] = []
    @State private var isLoading = false
    @State private var isEditingMetadata = false
    let database: DatabasePool
    
    // Editor State
    @State private var selectedTab: Int = 0
    @State private var mdTitle: String = ""
    @State private var mdArtist: String = ""
    @State private var mdAlbum: String = ""
    @State private var mdAlbumArtist: String = ""
    @State private var mdYear: String = ""
    @State private var mdTrackNumber: String = ""
    @State private var mdGenre: String = ""
    @State private var mdComposer: String = ""
    @State private var mdComment: String = ""
    @State private var mdPublisher: String = ""
    @State private var mdIsrc: String = ""
    @State private var mdBpm: String = ""
    @State private var mdArtworkData: Data? = nil
    @State private var showFileImporter = false
    @State private var isSavingMetadata = false
    @State private var showSaveSuccess = false
    
    // LRC parser helper
    struct LyricLine: Identifiable {
        let id = UUID()
        let time: Double?
        let text: String
    }
    
    var currentLineIndex: Int? {
        let currentProgress = playbackVM.playbackProgress * (playbackVM.currentTrack?.duration ?? 0)
        let lines = cachedParsedLyrics
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
        ZStack(alignment: .top) {
            // Transparent background (parent has the full blur)
            Color.black.opacity(0.4)
            
            VStack {
                Picker("", selection: $selectedTab) {
                    Text("Lyrics").tag(0)
                    Text("Metadata").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
                .padding(.top, 40)
                
                if selectedTab == 0 {
                    lyricsContent
                } else {
                    metadataContent
                }
            }
        }
        .onAppear { loadInitialData() }
        .onChange(of: playbackVM.currentTrack?.id) { _ in loadInitialData() }
    }
    
    private var lyricsContent: some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            } else if cachedParsedLyrics.isEmpty {
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
                            ForEach(Array(cachedParsedLyrics.enumerated()), id: \.element.id) { index, line in
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
    }
    
    private var metadataContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    Text(isEditingMetadata ? "Edit Track Metadata" : "Track Metadata")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: {
                        withAnimation { isEditingMetadata.toggle() }
                    }) {
                        Image(systemName: isEditingMetadata ? "pencil.circle.fill" : "pencil.circle")
                            .font(.title2)
                            .foregroundColor(.purple)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: 500)
                .padding(.horizontal)
                
                // Artwork Preview / Editor
                Button(action: {
                    if isEditingMetadata {
                        showFileImporter = true
                    }
                }) {
                    ZStack {
                        if let previewData = mdArtworkData, let nsImage = NSImage(data: previewData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFill()
                        } else if let filename = playbackVM.currentTrack?.albumArtworkPath,
                                  let cacheDir = ImageDownsampler.artworkCacheDirectory(),
                                  let nsImage = NSImage(contentsOfFile: cacheDir.appendingPathComponent(filename).path) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Rectangle()
                                .fill(Color.white.opacity(0.1))
                            Image(systemName: "music.note")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.3))
                        }
                        
                        if isEditingMetadata {
                            Rectangle()
                                .fill(Color.black.opacity(0.4))
                            Image(systemName: "camera.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 150, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(!isEditingMetadata)
                .fileImporter(
                    isPresented: $showFileImporter,
                    allowedContentTypes: [.image],
                    allowsMultipleSelection: false
                ) { result in
                    do {
                        guard let selectedFile = try result.get().first else { return }
                        if selectedFile.startAccessingSecurityScopedResource() {
                            defer { selectedFile.stopAccessingSecurityScopedResource() }
                            let data = try Data(contentsOf: selectedFile)
                            self.mdArtworkData = data
                        }
                    } catch {
                        print("Failed to load artwork image: \(error)")
                    }
                }
                
                VStack(spacing: 20) {
                    metadataSection(title: "Track Details") {
                        metadataField("Title", text: $mdTitle)
                        metadataField("Artist", text: $mdArtist)
                        metadataField("Album", text: $mdAlbum)
                        metadataField("Album Artist", text: $mdAlbumArtist)
                    }
                    
                    metadataSection(title: "Additional Info") {
                        metadataField("Track Number", text: $mdTrackNumber)
                        metadataField("Year", text: $mdYear)
                        metadataField("Genre", text: $mdGenre)
                    }
                    
                    metadataSection(title: "Production & Credits") {
                        metadataField("Composer", text: $mdComposer)
                        metadataField("BPM", text: $mdBpm)
                        metadataField("Publisher", text: $mdPublisher)
                        metadataField("ISRC", text: $mdIsrc)
                    }
                    
                    metadataSection(title: "Comments") {
                        metadataField("Comment", text: $mdComment)
                    }
                }
                .frame(maxWidth: 500)
                .padding(.horizontal)
                .disabled(!isEditingMetadata)
                
                if isEditingMetadata {
                    HStack(spacing: 20) {
                        if showSaveSuccess {
                            Text("Saved Successfully!")
                                .foregroundColor(.green)
                                .transition(.opacity)
                        }
                        
                        Button(action: saveMetadata) {
                            if isSavingMetadata {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Save Metadata")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .disabled(isSavingMetadata)
                    }
                    .padding(.bottom, 40)
                }
            }
            .padding(.top, 20)
        }
    }
    
    private func loadInitialData() {
        guard let track = playbackVM.currentTrack else {
            setLyrics(nil)
            return
        }
        
        mdTitle = track.title
        mdArtist = track.artistName ?? ""
        mdAlbum = track.albumTitle ?? ""
        
        // Try to fetch full album to get album artist and year
        if let albumTitle = track.albumTitle, let artistName = track.artistName {
            if let artistRec = try? database.read({ try ArtistRecord.filter(Column("name") == artistName).fetchOne($0) }),
               let albumRec = try? database.read({ try AlbumRecord.filter(Column("title") == albumTitle && Column("artistId") == artistRec.id).fetchOne($0) }) {
                mdAlbumArtist = albumRec.albumArtist ?? ""
                mdYear = albumRec.year.map { String($0) } ?? ""
            }
        }
        
        mdTrackNumber = track.trackNumber.map { String($0) } ?? ""
        mdGenre = track.genre ?? ""
        mdComposer = track.composer ?? ""
        mdComment = track.comment ?? ""
        mdPublisher = track.publisher ?? ""
        mdIsrc = track.isrc ?? ""
        mdBpm = track.bpm.map { String($0) } ?? ""
        
        if let l = track.lyrics, !l.isEmpty {
            setLyrics(l)
        } else {
            setLyrics(nil)
        }
    }
    
    private func saveMetadata() {
        guard let track = playbackVM.currentTrack else { return }
        isSavingMetadata = true
        showSaveSuccess = false
        
        let path = track.filePath
        let title = mdTitle
        let artist = mdArtist
        let album = mdAlbum
        let albumArtist = mdAlbumArtist
        let year = Int32(mdYear) ?? 0
        let trackNumber = Int32(mdTrackNumber) ?? 0
        let genre = mdGenre
        let composer = mdComposer
        let comment = mdComment
        let publisher = mdPublisher
        let isrc = mdIsrc
        let bpm = UInt32(mdBpm) ?? 0
        let trackId = track.id
        let newArtworkData = mdArtworkData
        
        Task.detached(priority: .userInitiated) {
            // 1. Save to FLAC file via TagLib C++ Bridge
            let success = UpdateFLACMetadata(
                path,
                title.isEmpty ? nil : title,
                artist.isEmpty ? nil : artist,
                album.isEmpty ? nil : album,
                albumArtist.isEmpty ? nil : albumArtist,
                UInt32(year),
                UInt32(trackNumber),
                0, // discNumber unchanged for now
                genre.isEmpty ? nil : genre,
                composer.isEmpty ? nil : composer,
                comment.isEmpty ? nil : comment,
                publisher.isEmpty ? nil : publisher,
                isrc.isEmpty ? nil : isrc,
                bpm
            )
            
            var newArtworkFilename: String? = nil
            if success, let artworkData = newArtworkData {
                // Update artwork in FLAC
                artworkData.withUnsafeBytes { ptr in
                    if let baseAddress = ptr.baseAddress {
                        _ = UpdateFLACArtwork(path, baseAddress, artworkData.count, "image/jpeg")
                    }
                }
                
                // Downsample and cache locally
                if let cacheDir = ImageDownsampler.artworkCacheDirectory() {
                    newArtworkFilename = ImageDownsampler.downsampleAndCache(
                        artworkData: artworkData,
                        cacheDirectory: cacheDir
                    )
                }
            }
            
            if success {
                // 2. Update local DB
                do {
                    try self.database.updateTrackMetadata(
                        trackId: trackId,
                        title: title,
                        artist: artist,
                        album: album,
                        albumArtist: albumArtist,
                        year: Int(year),
                        trackNumber: Int(trackNumber),
                        genre: genre.isEmpty ? nil : genre,
                        composer: composer.isEmpty ? nil : composer,
                        comment: comment.isEmpty ? nil : comment,
                        publisher: publisher.isEmpty ? nil : publisher,
                        isrc: isrc.isEmpty ? nil : isrc,
                        bpm: bpm > 0 ? Int(bpm) : nil,
                        artworkCachePath: newArtworkFilename
                    )
                } catch {
                    print("Failed to update database: \(error)")
                }
            }
            
            await MainActor.run {
                self.isSavingMetadata = false
                if success {
                    withAnimation { self.showSaveSuccess = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { self.showSaveSuccess = false }
                    }
                }
            }
        }
    }
    
    private func setLyrics(_ text: String?) {
        self.lyrics = text
        guard let text = text else {
            self.cachedParsedLyrics = []
            return
        }
        
        self.cachedParsedLyrics = text.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return nil }
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
    
    private func fetchLyrics() async {
        guard let track = playbackVM.currentTrack else { return }
        isLoading = true
        do {
            let fetched = try await LyricsService.shared.fetchAndEmbedLyrics(for: track, database: database)
            await MainActor.run {
                self.setLyrics(fetched)
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

// MARK: - View Helpers
extension LyricsOverlayView {
    
    private func metadataSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.gray)
                .padding(.bottom, 4)
            
            VStack(spacing: 0) {
                content()
            }
            .background(Color.white.opacity(0.05))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
    
    private func metadataField(_ placeholder: String, text: Binding<String>) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(placeholder)
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 120, alignment: .leading)
                
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
            }
            .padding()
            
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.leading, 120 + 16)
        }
    }
}
