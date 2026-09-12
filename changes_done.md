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
