# YM Pro - Completed Features Log

This document tracks major features and architectural improvements that have been successfully implemented into YM Pro.

## Core Audio & Architecture

**1. Bit-Perfect & DAC Auto-Sample Rate Switching**
* **Status:** Completed
* **Details:** The CoreAudio HAL engine now completely bypasses the macOS system mixer. It dynamically locks the external DAC hardware to the exact sample rate of the currently playing FLAC file, ensuring flawless bit-perfect output.

**2. Gapless Playback & EOF Handling**
* **Status:** Completed
* **Details:** The C-level libFLAC decoding worker uses a lock-free ring buffer and precise frame counting to transition between tracks. Premature audio cutoff (the "3 seconds before end" bug) has been resolved.

**3. Background Folder Auto-Monitoring (FSEvents)**
* **Status:** Completed
* **Details:** The app leverages native macOS `FSEvents` to automatically watch library folders for additions and deletions, keeping the database perfectly in sync without manual scanning.

**4. Clutter-Free Artist Extraction**
* **Status:** Completed
* **Details:** The library scanner uses aggressive delimiter splitting to clean up FLAC `ARTIST` tags, ensuring that "Featured" artists don't spawn duplicate/cluttered profiles in the Artists view.

**5. Nerd-Grade UI & Settings**
* **Status:** Completed
* **Details:** Integrated a dedicated "Audio Engine & Devices" settings panel for granular control over Hog Mode, ReplayGain, Gapless Playback, and Bit-Perfect settings. Removed the bulky logo for a sleek "Add Folders" quick-action button.

**6. Compilation Album Grouping Fix (Album Artist)**
* **Status:** Completed
* **Details:** Updated `LibraryScanner.swift` to properly group `AlbumRecord` using the `Album Artist` tag (or fallback to main artist) so that DJ Mixes and collaboration albums don't fracture into multiple albums in the UI.

**7. Up Next / Queue State Sync Bug**
* **Status:** Completed
* **Details:** Fixed the UI state bug where manually adding tracks to the queue does not correctly or immediately update the visual "Up Next" list, ensuring perfect synchronization between the playback engine and UI.

**8. Network Drive FSEvents Safety**
* **Status:** Completed
* **Details:** Added safety checks in the boot sequence so that if a watched network drive (NAS) is unreachable, the app gracefully ignores it instead of crashing.

**9. Parametric Equalizer (EQ) & DSP Crossfeed**
* **Status:** Completed
* **Details:** Implemented a built-in highly customizable 10-band Graphic EQ and a Bauer "Crossfeed" DSP algorithm directly at the C/C++ audio render layer for optimal lock-free real-time performance. Added a beautiful UI slider module to control it.

**10. Tracks View Multi-Selection & UI Overhaul**
* **Status:** Completed
* **Details:** Re-architected the `TracksView` to use native SwiftUI Table column customizations. Merged quality columns to fit native limits, added explicit file size column and total size headers. Built a robust, custom Shift-Click range selection handler inside the checkboxes that bypasses macOS Table quirks.

**11. Context Menu & File Integration**
* **Status:** Completed
* **Details:** Added in-place "Toggle Favorite" with an animated scale/spring heart icon in the title cell, avoiding full-page reloads. Integrated native "Show in Finder" functionality directly into the Tracks right-click context menu.

**12. Database Preservation on Rescan**
* **Status:** Completed
* **Details:** Fixed a critical data-loss bug in `LibraryScanner.swift` where background auto-watching and manual rescans would blindly overwrite tracks and reset user metrics. Scans now correctly preserve `playCount`, `lastPlayedAt`, and `isFavorite` metrics during upserts.

**13. Adaptive Dark/Light Mode Modals**
* **Status:** Completed
* **Details:** Replaced hardcoded `Color.primary` opacity overlays in `LyricsOverlayView` and `FullScreenPlayerView` with native Apple `Material` (e.g. `.regularMaterial`). This ensures the modals and frosted glass blur adapt perfectly and legibly whether the user's macOS system is in Light Mode or Dark Mode.

**14. Tracks View Multi-Key Chronological Sub-sorting**
* **Status:** Completed
* **Details:** Updated the `TracksView` in-memory sorting layer to support deep multi-key sub-sorting. When sorting the massive tracks list by Artist or Album, the engine now correctly cascades the sort (`Artist -> Album -> Disc Number -> Track Number`), preventing conceptual albums from scrambling out of order.

**15. Tracks View Quality & Type Sorting Logic**
* **Status:** Completed
* **Details:** Re-wrote the column sorting logic in `TracksView` to support perfect "Quality" cascading. Sorting by the Quality column now cascades correctly via: `Sample Rate -> Bit Depth -> Bitrate -> Album -> Disc Number -> Track Number`. Sorting by "Type" now correctly groups files by extension (FLAC/MP3/M4A) and sub-sorts by Album.

**16. ID3 & FLAC Metadata Editor UI**
* **Status:** Completed
* **Details:** Built a dedicated, natively styled Metadata Editor directly into the Lyrics/Metadata modal. Users can directly view and edit tags like Title, Artist, Album, Genre, Composer, and BPM without leaving the app.

**17. Table Column Resizing & Reordering**
* **Status:** Completed
* **Details:** Added `TableColumnCustomization` bindings and customization IDs to the SwiftUI `Table` in the Tracks view. This unlocks native macOS QoL features, allowing users to resize, reorder, and hide columns.

**18. Advanced Audio Waveform Seekbar**
* **Status:** Completed
* **Details:** Built a custom `WaveformGenerator` and `WaveformView` inside `NowPlayingBar`. It reads sparse chunks of the audio file to rapidly render a visual, interactive waveform representation of the track instead of a standard linear slider.

**19. Track View Performance & Pagination**
* **Status:** Completed
* **Details:** Refactored the SwiftUI Table and database queries to use strict lazy-loading and GRDB pagination. Replaced in-memory Swift sorting with optimized SQL `ORDER BY` execution. Implemented `.onAppear` infinite scrolling and added `fetchDistinctFilePaths()` to dramatically speed up folder tree rendering without loading massive track arrays.

**20. View Modes (List vs. Grid Toggle)**
* **Status:** Completed
* **Details:** Allowed users to toggle between the current Grid view (portraits/covers) and a dense List view for the Artists and Albums pages.

**21. Now Playing Inspector & Liquid Glass UI**
* **Status:** Completed
* **Details:** Added a collapsible right sidebar inspector showing the "Up Next" queue and large album artwork. Upgraded the background to natively use macOS `ultraThinMaterial` for an Apple Music-style liquid glass frosted effect. Built a custom Drag-and-Drop system to visually reorder the playing queue. Polished the window size logic so sidebars auto-collapse on smaller screens, preventing overlapping content.

**22. Artist Library Metadata Aggregation Fix**
* **Status:** Completed
* **Details:** Fixed the SQL logic in `AppDatabase.swift` that calculates album and track counts. Artists now properly get credit for tracks if they are the Track Artist *or* if they are the Album Artist of the track's album (fixing the "3 Albums, 0 Songs" bug).

**23. Custom Theming Engine & Accent Colors**
* **Status:** Completed
* **Details:** Built a comprehensive theme engine allowing users to pick custom UI accent colors and toggle the intensity of the glassmorphism blur in both Light and Dark mode, making the app feel uniquely theirs.

**24. Mini-Player "Always on Top" Mode**
* **Status:** Completed
* **Details:** The existing mini-player window (launched from the bottom playback bar) now automatically sets its NSWindow level to .floating and joins all spaces on appear. This means it floats above every other app window and follows you across all Mission Control desktops and full-screen spaces.

**25. Legacy Intel MacBook Support (Universal Binary)**
* **Status:** Completed
* **Details:** Configured the Xcode project to build as a Universal Binary (`arm64` + `x86_64`) and lowered the macOS deployment target to support older Intel-based Macs. Expands the user base to audiophiles who still use older Intel Macs as dedicated media servers or desktop setups.

## Version 2.2 (Golden Gate Update)

**26. "Floating Island" Transport UI**
* **Status:** Completed
* **Details:** Modernized the Now Playing bar into a floating, ultra-thin glassmorphic pill detached from the window edges (inspired by macOS Golden Gate paradigms). Added tactile hover expansions to the playback scrubber.

**27. High-Frequency SwiftUI Render Optimization**
* **Status:** Completed
* **Details:** Resolved a severe constraint loop crash and UI flickering (e.g., Settings tab bar flashing 4x/sec). Isolated the high-frequency `@ObservedObject playbackVM` timer ticks away from the main `ContentView` and `SettingsView` shell, pushing the subscriptions down to dedicated leaf components (`DetailContentView` and `AudioTabDSPControls`).

**28. Golden Gate UI (Native Liquid Glass)**
* **Status:** Completed
* **Details:** Complete visual overhaul of the application using native macOS `.glassEffect` (Liquid Glass). Replaced muddy `.ultraThinMaterial` backgrounds with a gorgeous, premium translucent layer across the Now Playing Bar, Queue Popover, Full-Screen Player (Lyrics), and Album Detail overlays.

**29. Native Finder File Association**
* **Status:** Completed
* **Details:** Implemented `.onOpenURL` and `CFBundleDocumentTypes` to allow YM Pro to act as the default audio player on macOS. Double-clicking any supported audio file in Finder instantly launches the app and plays the track ephemerally (without permanently cluttering the user's curated library).

**30. Direct Feedback & Support Hub**
* **Status:** Completed
* **Details:** Added a dedicated "Report Bug / Feedback" integration in the Settings menu that links directly to the project's GitHub Issues page, allowing users to quickly request features or report bugs without heavy analytics tracking.

## Version 2.2.2 (Network Playback Overhaul)

**31. Network Drive Playback Stability**
* **Status:** Completed
* **Details:** Wrapped C++ decoder initialization in detached background tasks to prevent severe UI blocking (e.g., 15-minute beachballs) when loading heavy metadata over high-latency network drives.

**32. Hysteresis Rebuffering Architecture**
* **Status:** Completed
* **Details:** Redesigned the Core Audio ring buffer worker to use Hysteresis Rebuffering. If the network stalls, the engine now cleanly pauses playback and stockpiles a 50% buffer (45 seconds of audio) before resuming, entirely eliminating rapid audio flickering and stuttering on slow internet.

**33. Library Pagination & True Track Counts**
* **Status:** Completed
* **Details:** Fixed an issue where the library view truncated at 5,000 tracks. Restored lazy-loading pagination, and added a highly efficient database-level `COUNT()` query to instantly display the true total track count at the top of the Library view (e.g., "8,000 tracks") regardless of the current pagination offset.
