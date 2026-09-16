# YM Pro - Future Roadmap & Feature Plan

This document outlines potential future enhancements for YM Pro to elevate it from a great local music player to an industry-leading audiophile application. The features are ranked by priority, focusing on core audio quality and user experience first.



## 🔴 High Priority (Core Audio & UX Needs)

**1. Fortify Gapless Transition Scrubbing State Machine**
* **Description:** Refine the state machine in `PlaybackViewModel` and the HAL engine so that seeking (scrubbing) during a cross-track transition doesn't freeze the playback thread.
* **Why it matters:** Ensures the app feels robust and unbreakable when users rapidly skip or scrub exactly when a track is changing.

**2. ReplayGain Calculator & Editor**
* **Description:** Build a dedicated C/C++ audio analysis integration to calculate ReplayGain loudness values for tracks/albums, and write the tags back to the physical FLAC files. (Note: Basic ID3/FLAC metadata editing is already complete in the UI).
* **Why it matters:** Eliminates the need for users to rely on external tools like Foobar2000 to normalize volume levels.

## 🟡 Medium Priority (Engagement & Advanced Tools)

**3. Drag & Drop Library Import**
* **Description:** Add native macOS drag-and-drop support so users can drag folders or FLAC files directly from Finder onto the app window to add them to the library.
* **Why it matters:** Standard Mac behavior that users expect; faster than using the folder picker.

**4. Add Folders to Queue**
* **Description:** Allow users to right-click an entire folder from a hierarchy view and add all contained tracks directly to the playing queue.
* **Why it matters:** Crucial for users who prefer organizing and listening to music strictly by folder hierarchy rather than by ID3 tags like Albums/Artists.
**5. DLNA & AirPlay 2 Casting**
* **Description:** Built-in protocol support to cast the high-res audio stream directly to networked AV receivers, smart TVs, or HomePods.
* **Why it matters:** Expanding playback beyond the Mac's physical audio jacks.

**6. Smart Playlists & Dynamic Filters**
* **Description:** Playlists that auto-populate based on rules (e.g., "Added in the last 30 days", "Play count > 50", "Genre = Jazz").
* **Why it matters:** Helps power users rediscover their massive libraries without manual playlist curation.

**7. Last.fm / ListenBrainz Scrobbling**
* **Description:** Background syncing of listening history to tracking services.
* **Why it matters:** Highly requested feature by music enthusiasts who want to maintain historical statistics of their listening habits.



**9. Playlist Export and Import**
* **Description:** Allow users to export and import M3U or standard playlist formats.
* **Why it matters:** Ensures playlist portability across different devices and players.

**10. Predefined Headphone EQs**
* **Description:** Ship with AutoEQ presets for popular audiophile headphones.
* **Why it matters:** A massive quality of life upgrade for headphone listeners.

**11. Audio Upsampling / Resampling**
* **Description:** Add DSP options for high-quality upsampling (e.g., 44.1kHz to 192kHz) before sending to the DAC.
* **Why it matters:** Highly requested by audiophiles wanting to feed their DACs with specific, consistent high-resolution streams.

## 🟢 Low Priority (Nice-to-Haves & Ecosystem)

**12. Sleep Timer**
* **Description:** A quick menu option to fade out and pause playback after 15/30/60 minutes.
* **Why it matters:** Perfect for bedtime listening.

**13. Built-in Format Converter**
* **Description:** Right-click a FLAC album and export it as ALAC, MP3, or AAC to a target folder.
* **Why it matters:** Useful for users syncing music to older iPods or devices with limited storage that don't support high-res FLAC.

**14. Companion Mobile Remote Control App (iOS & Android)**
* **Description:** A lightweight companion app that connects to the Mac via local Wi-Fi to pause, play, and browse the queue.
* **Why it matters:** Allows users listening on living room stereo systems to control their Mac from the couch.

**15. External Streaming Integrations (Apple Music/Tidal/Qobuz)**
* **Description:** Add API connections for audiophile streaming services like Qobuz, Tidal, or Apple Music (non-DRM) alongside the local library.
* **Why it matters:** Merges the convenience of streaming with the uncompromising quality of the local FLAC engine.

**16. Home Assistant & Music Assistant Integration**
* **Description:** Build a plugin or local API endpoint that allows YM Pro to be controlled by Home Assistant or act as a provider for Music Assistant.
* **Why it matters:** Huge value for smart-home power users who want to automate playback or cast to different zones using HA.

**17. Windows / Cross-Platform Port**
* **Description:** Evaluate open-sourcing the core logic for a Windows C++/C# build to meet high demand from Windows audiophiles.
* **Why it matters:** Captures the massive Windows market currently relying on Foobar2000.
