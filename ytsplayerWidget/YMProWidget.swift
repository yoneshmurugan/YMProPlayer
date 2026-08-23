import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), title: "YM Pro", artist: "Nothing Playing", artworkPath: nil, isPlaying: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let defaults = UserDefaults(suiteName: "group.com.ympro.mac")
        let title = defaults?.string(forKey: "widget_title") ?? "YM Pro"
        let artist = defaults?.string(forKey: "widget_artist") ?? "Nothing Playing"
        let artworkPath = defaults?.string(forKey: "widget_artworkPath")
        let isPlaying = defaults?.bool(forKey: "widget_isPlaying") ?? false
        
        let entry = SimpleEntry(date: Date(), title: title, artist: artist, artworkPath: artworkPath, isPlaying: isPlaying)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> ()) {
        let defaults = UserDefaults(suiteName: "group.com.ympro.mac")
        let title = defaults?.string(forKey: "widget_title") ?? "Nothing Playing"
        let artist = defaults?.string(forKey: "widget_artist") ?? ""
        let artworkPath = defaults?.string(forKey: "widget_artworkPath")
        let isPlaying = defaults?.bool(forKey: "widget_isPlaying") ?? false
        
        let entry = SimpleEntry(date: Date(), title: title, artist: artist, artworkPath: artworkPath, isPlaying: isPlaying)
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
    
    private func getCurrentEntry() -> SimpleEntry {
        let defaults = UserDefaults(suiteName: "group.com.ytsplayer.YMPro")
        let title = defaults?.string(forKey: "currentTrackTitle") ?? "YM Pro"
        let artist = defaults?.string(forKey: "currentTrackArtist") ?? "Nothing Playing"
        let artworkPath = defaults?.string(forKey: "currentTrackArtworkPath")
        let isPlaying = defaults?.bool(forKey: "isPlaying") ?? false
        
        return SimpleEntry(date: Date(), title: title, artist: artist, artworkPath: artworkPath, isPlaying: isPlaying)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let artworkPath: String?
    let isPlaying: Bool
}

extension View {
    @ViewBuilder
    func widgetBackground<T: View>(_ backgroundView: T) -> some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            self.containerBackground(for: .widget) {
                backgroundView
            }
        } else {
            self.background(backgroundView)
        }
    }
}

struct YMProWidgetEntryView : View {
    var entry: Provider.Entry
    
    var artworkURL: URL? {
        if entry.artworkPath == nil || entry.artworkPath?.isEmpty == true { return nil }
        let fileManager = FileManager.default
        if let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ympro.mac") {
            let url = groupURL.appendingPathComponent("widget_artwork.jpg")
            return fileManager.fileExists(atPath: url.path) ? url : nil
        }
        return nil
    }

    var body: some View {
        VStack {
            Spacer()
            
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(entry.artist)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                }
                
                Spacer()
                
                if entry.isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
        }
        .widgetBackground(
            Group {
                if let url = artworkURL, let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(colors: [Color.purple.opacity(0.8), Color.blue.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
        )
    }
}

@main
struct YMProWidget: Widget {
    let kind: String = "YMProWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            YMProWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("YM Pro")
        .description("See what's currently spinning.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
