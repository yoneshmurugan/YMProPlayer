// ImageLoader.swift
// ytsplayer

import SwiftUI
import Combine

class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, NSImage>()
    
    init() {
        cache.countLimit = 1000 // Max 1000 images in memory
    }
    
    func get(for url: URL) -> NSImage? {
        return cache.object(forKey: url as NSURL)
    }
    
    func set(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

class ImageLoader: ObservableObject {
    @Published var image: NSImage?
    var url: URL
    private var cancellable: AnyCancellable?
    
    init(url: URL) {
        self.url = url
    }
    
    func load() {
        if let cached = ImageCache.shared.get(for: url) {
            self.image = cached
            return
        }
        
        self.image = nil
        
        // Read file async to not block main thread, instead of URLSession since these are local files
        cancellable = Future<NSImage?, Never> { [url] promise in
            DispatchQueue.global(qos: .userInitiated).async {
                if let data = try? Data(contentsOf: url), let img = NSImage(data: data) {
                    promise(.success(img))
                } else {
                    promise(.success(nil))
                }
            }
        }
        .handleEvents(receiveOutput: { [weak self, url] img in
            if let img = img {
                ImageCache.shared.set(img, for: url)
            }
        })
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.image = $0 }
    }
    
    func cancel() {
        cancellable?.cancel()
    }
}

struct CachedAsyncImage<Placeholder: View>: View {
    @StateObject private var loader: ImageLoader
    let url: URL
    private let placeholder: Placeholder
    
    init(url: URL, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        _loader = StateObject(wrappedValue: ImageLoader(url: url))
        self.placeholder = placeholder()
    }
    
    var body: some View {
        Group {
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
            } else {
                placeholder
            }
        }
        .onAppear {
            loader.load()
        }
        .onChange(of: url) { newURL in
            loader.cancel()
            loader.url = newURL
            loader.load()
        }
        .onDisappear {
            loader.cancel()
        }
    }
}
