# YM Pro - Future Roadmap & Feature Plan

This document outlines potential future enhancements for YM Pro to elevate it from a great local music player to an industry-leading audiophile application. The features are ranked by priority, focusing on core audio quality and user experience first.

## 🔴 High Priority (Core Audio & UX Needs)

**1. Compilation Album Grouping Fix (Album Artist)**
* **Description:** Update `LibraryScanner.swift` to properly group `AlbumRecord` using the `Album Artist` tag (or fallback to main artist) so that DJ Mixes and collaboration albums don't fracture into multiple albums in the UI.
* **Why it matters:** Essential for users with large libraries of compilations and features.

**2. Chronological Track Sorting (Multi-Key Sub-sorting)**
* **Description:** When viewing an album or sorting the Tracks view by Artist or Album, the database fetch should enforce a multi-sort: `Artist -> Album -> Disc Number -> Track Number`.
* **Why it matters:** Currently, songs can play out of order when clicking an album or sorting by Artist, ruining conceptual records.

**3. Up Next / Queue State Sync Bug**
* **Description:** Fix the UI state bug where manually adding tracks to the queue does not correctly or immediately update the visual "Up Next" list.
* **Why it matters:** Users rely heavily on the queue; if the visual list doesn't update, the app feels broken and unresponsive.

**4. Network Drive FSEvents Safety**
* **Description:** Add safety checks in the boot sequence so that if a watched network drive (NAS) is unreachable, the app gracefully ignores it instead of crashing.
* **Why it matters:** A crash loop on launch makes the app unusable for NAS listeners.

**4. Advanced Gapless & Cross-Track Scrubbing State Machine**
* **Description:** Refine the state machine in `PlaybackViewModel` and the HAL engine so that seeking (scrubbing) during a cross-track transition doesn't freeze the playback thread.
* **Why it matters:** Ensures the app feels robust and unbreakable when users rapidly skip or scrub.

**5. Full Metadata & ReplayGain Editor UI**
* **Description:** Build a dedicated window to edit ID3/FLAC metadata tags and calculate/edit ReplayGain values for the library.
* **Why it matters:** Eliminates the need for users to rely on external tools like Foobar2000.

## 🟡 Medium Priority (Engagement & Advanced Tools)

**7. Drag & Drop Library Import**
* **Description:** Add native macOS drag-and-drop support so users can drag folders or FLAC files directly from Finder onto the app window to add them to the library.
* **Why it matters:** Standard Mac behavior that users expect; faster than using the folder picker.

**8. View Modes (List vs. Grid Toggle)**
* **Description:** Allow users to toggle between the current Grid view (portraits/covers) and a dense List view for the Artists and Albums pages.
* **Why it matters:** Power users with massive libraries often prefer dense text lists over large grid thumbnails.

**9. Track View Performance & Pagination**
* **Description:** Refactor the SwiftUI `Table` and `List` views to use strict lazy-loading and GRDB pagination.
* **Why it matters:** Fixes sluggish UI loading times when viewing and re-sorting 2000+ tracks.

**10. SwiftUI Table Column Resizing & Reordering**
* **Description:** Add native macOS table customizations so users can resize and rearrange columns in the Tracks view.
* **Why it matters:** Highly requested QoL feature for desktop users.

**5. Parametric Equalizer (EQ) & DSP Crossfeed**
* **Description:** Implement a built-in highly customizable EQ and a "Crossfeed" DSP toggle.
* **Why it matters:** Crossfeed reduces listener fatigue for headphone users by blending extreme stereo separation, simulating the experience of listening to physical room speakers.

**6. DLNA & AirPlay 2 Casting**
* **Description:** Built-in protocol support to cast the high-res audio stream directly to networked AV receivers, smart TVs, or HomePods.
* **Why it matters:** Expanding playback beyond the Mac's physical audio jacks.

**7. Smart Playlists & Dynamic Filters**
* **Description:** Playlists that auto-populate based on rules (e.g., "Added in the last 30 days", "Play count > 50", "Genre = Jazz").
* **Why it matters:** Helps power users rediscover their massive libraries without manual playlist curation.

**8. Last.fm / ListenBrainz Scrobbling**
* **Description:** Background syncing of listening history to tracking services.
* **Why it matters:** Highly requested feature by music enthusiasts who want to maintain historical statistics of their listening habits.

**9. Advanced Audio Waveform Seekbar**
* **Description:** Replace or augment the standard linear seek bar with a visual representation of the track's audio waveform.
* **Why it matters:** Provides a visually striking UI element that helps users visually locate drops, choruses, and quiet sections.

**10. Mini-Player "Always on Top" Mode**
* **Description:** An option to detach a tiny, beautiful album-art focused mini-player that floats above all other macOS windows.
* **Why it matters:** Great for users who want to control music quickly while working in other full-screen apps.

## 🟢 Low Priority (Nice-to-Haves & Ecosystem)

**8. Legacy Intel MacBook Support (Universal Binary)**
* **Description:** Configure the Xcode project to build as a Universal Binary (`arm64` + `x86_64`) and evaluate lowering the macOS deployment target (e.g., to macOS 12) to support older Intel-based Macs.
* **Why it matters:** Expands the user base to audiophiles who still use older Intel Macs as dedicated media servers or desktop setups.

**9. Sleep Timer**
* **Description:** A quick menu option to fade out and pause playback after 15/30/60 minutes.
* **Why it matters:** Perfect for bedtime listening.

**12. Built-in Format Converter**
* **Description:** Right-click a FLAC album and export it as ALAC, MP3, or AAC to a target folder.
* **Why it matters:** Useful for users syncing music to older iPods or devices with limited storage that don't support high-res FLAC.

**13. Custom Theming Engine & Light Mode**
* **Description:** Allow users to switch between the default dark mode and a bright, clean Light Mode. Additionally, let users pick UI accent colors and toggle the intensity of the glassmorphism blur.
* **Why it matters:** Personalization adds a premium feel to the app, and light mode is highly requested for daytime listening or bright environments.

**15. Companion iOS Remote Control App**
* **Description:** A lightweight companion iPhone app that connects to the Mac via local Wi-Fi to pause, play, and browse the queue.
* **Why it matters:** Allows users listening on living room stereo systems to control their Mac from the couch.

**16. External Streaming Integrations (Tidal/Qobuz)**
* **Description:** Add API connections for audiophile streaming services like Qobuz or Tidal alongside the local library.
* **Why it matters:** Merges the convenience of streaming with the uncompromising quality of the local FLAC engine.

**17. Home Assistant & Music Assistant Integration**
* **Description:** Build a plugin or local API endpoint that allows YM Pro to be controlled by Home Assistant or act as a provider for Music Assistant.
* **Why it matters:** Huge value for smart-home power users who want to automate playback or cast to different zones using HA.
