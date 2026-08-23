import AVFoundation

let inputURL = URL(fileURLWithPath: "/Users/yonesh/Projects/Player/ytsplayer/Assets/Create_intro_video_for_application_202608232059_gwr_video_mvp.mp4")
let outputURL = URL(fileURLWithPath: "/Users/yonesh/Projects/Player/ytsplayer/Assets/intro_video.mp4")

try? FileManager.default.removeItem(at: outputURL)

let asset = AVAsset(url: inputURL)
let composition = AVMutableComposition()

guard let videoTrack = asset.tracks(withMediaType: .video).first else {
    print("No video track found")
    exit(1)
}

guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
    print("Failed to add video track")
    exit(1)
}

do {
    try compVideoTrack.insertTimeRange(CMTimeRangeMake(start: .zero, duration: asset.duration), of: videoTrack, at: .zero)
} catch {
    print("Failed to insert time range: \(error)")
    exit(1)
}

guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
    print("Failed to create export session")
    exit(1)
}

exportSession.outputURL = outputURL
exportSession.outputFileType = .mp4

let semaphore = DispatchSemaphore(value: 0)

exportSession.exportAsynchronously {
    if exportSession.status == .completed {
        print("Success")
    } else if let error = exportSession.error {
        print("Failed: \(error)")
    }
    semaphore.signal()
}

semaphore.wait()
