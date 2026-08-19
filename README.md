# YTSPlayer

A lightweight, native macOS audiophile FLAC player with Bit-Perfect CoreAudio HAL output, built with SwiftUI, C/C++ TagLib, and GRDB SQLite. 

Designed for speed and pristine audio quality, YTSPlayer bypasses the macOS system mixer entirely to deliver exclusive, bit-perfect hardware playback straight to your DAC.

## Features

- **Bit-Perfect CoreAudio HAL**: Direct Hardware Abstraction Layer integration for zero-tamper audio playback.
- **Hog Mode (Exclusive Access)**: Bypasses the macOS system mixer and grants the app exclusive lock-on to your DAC.
- **Zero-Stutter Background Decoding**: Headless C-based `libFLAC` worker thread decodes audio chunks on a background GCD queue, ensuring the UI remains buttery smooth.
- **Blazing Fast Library Scanner**: Concurrent Swift tasks + GRDB SQLite batch inserts + custom C++ TagLib bindings to scan thousands of FLACs in seconds.
- **Dynamic Hi-Res Badges**: Automatically detects and highlights high-resolution audio (e.g. 24-bit / 96kHz).
- **Beautiful Native UI**: Built 100% in SwiftUI with modern glassmorphism, dynamic badge coloring, and seamless animations.

## Architecture

- **UI Layer**: SwiftUI `(macOS 13.0+)`
- **Database Layer**: GRDB (SQLite) with FTS5 for instant library search.
- **Metadata Layer**: C++ bridge interacting directly with `TagLib` for case-insensitive `PropertyMap` extraction and artwork downsampling.
- **Playback Engine**: Pure C-worker (`FLACDecoderWorker.c`) piping PCM buffers directly into a Swift `CoreAudioHALEngine`.

## Prerequisites

- **macOS 13.0** or later
- **Xcode 14.0** or later
- **Homebrew** (for managing dependencies)

## Installation & Setup

1. **Install Dependencies**
   The project requires `xcodegen` for project generation, and `flac` / `taglib` for the audio backend.
   ```bash
   brew install xcodegen flac taglib
   ```

2. **Generate the Xcode Project**
   Since the project structure is maintained via `project.yml`, generate the `.xcodeproj` file by running:
   ```bash
   xcodegen generate
   ```

3. **Build & Run**
   Open the generated project in Xcode:
   ```bash
   open ytsplayer.xcodeproj
   ```
   Select your Mac as the destination and hit **Run (Cmd + R)**.

## Usage

1. Open the app and navigate to **Settings**.
2. Click the folder icon under **Music Folder** and select the directory containing your `.flac` files.
3. The app will rapidly scan the folder, extract Vorbis Comments (tags), and generate album artwork thumbnails.
4. Go to the **Library** tab to view your albums.
5. In **Settings**, you can toggle **Hog Mode** to enable exclusive DAC access (Note: this will fail if you are using built-in speakers or if another app is currently holding an audio lock).

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## License

MIT License
