// SettingsView.swift
// ytsplayer

import SwiftUI
import CoreAudio

struct SettingsView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    // NOTE: playbackVM is passed as a plain `let` here, NOT @ObservedObject.
    // Using @ObservedObject caused SettingsView to re-render on every
    // playback timer tick (~4x/sec), which made the Picker tab bar flicker.
    // The DSP-dependent sub-expressions are isolated in AudioTabDSPControls.
    let playbackVM: PlaybackViewModel
    let halEngine: CoreAudioHALEngine

    @State private var showFolderPicker = false
    @State private var availableRates: [Double] = []
    @AppStorage("allowDownsampling") private var allowDownsampling = false
    @AppStorage("isGaplessEnabled") private var isGaplessEnabled = false
    @AppStorage("isBitPerfect") private var isBitPerfect = true
    @AppStorage("hogModeEnabled") private var hogModeEnabled = false
    @AppStorage("replayGainMode") private var replayGainMode = "off"
    @Environment(\.dismiss) var dismiss
    
    @State private var outputDevices: [AudioDevice] = CoreAudioController.shared.getAvailableOutputDevices()
    @AppStorage("outputDeviceID") private var selectedDeviceID: String = ""
    @EnvironmentObject var themeManager: ThemeManager

    @State private var selectedTab: String = "appearance"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ZStack {
                Text("Settings")
                    .font(.headline)
                
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close Settings")
                }
            }
            .padding()
            
            Picker("", selection: $selectedTab) {
                Text("Appearance").tag("appearance")
                Text("Library").tag("library")
                Text("Audio").tag("audio")
                Text("About").tag("about")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 60)
            .padding(.bottom, 16)
            
            Divider()
            
            Group {
                switch selectedTab {
                case "appearance": appearanceTab
                case "library": libraryTab
                case "audio": audioTab
                case "about": aboutTab
                default: appearanceTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            hogModeEnabled  = halEngine.isHogMode
            availableRates  = halEngine.availableSampleRates()
            
            outputDevices = CoreAudioController.shared.getAvailableOutputDevices()
            if selectedDeviceID.isEmpty {
                selectedDeviceID = String(halEngine.currentDeviceID)
            }

            // Restore saved library paths
            libraryVM.loadFoldersFromUserDefaults()
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                _ = url.startAccessingSecurityScopedResource()
                libraryVM.addFolder(url: url)
                libraryVM.startScan()
            }
        }
    }
    
    // MARK: - Tabs
    
    private var appearanceTab: some View {
        Form {
            Section("UI & Theming") {
                Picker("Theme Mode", selection: $themeManager.themeMode) {
                    ForEach(AppThemeMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                
                Picker("Accent Color", selection: $themeManager.accentColor) {
                    ForEach(AppAccentColor.allCases) { color in
                        HStack {
                            Circle()
                                .fill(color.color)
                                .frame(width: 12, height: 12)
                            Text(color.rawValue)
                        }.tag(color)
                    }
                }
                
                Picker("Glassmorphism Blur", selection: $themeManager.glassIntensity) {
                    ForEach(GlassIntensity.allCases) { intensity in
                        Text(intensity.rawValue).tag(intensity)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
    
    private var libraryTab: some View {
        Form {
            Section("Library Folders") {
                if libraryVM.libraryFolders.isEmpty {
                    Text("No folders selected")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(libraryVM.libraryFolders, id: \.self) { url in
                        HStack {
                            Text(url.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                libraryVM.removeFolder(url: url)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Button("Add Folder…") { showFolderPicker = true }
                
                HStack {
                    Button("Re-scan All") {
                        libraryVM.startScan()
                    }
                    .disabled(libraryVM.libraryFolders.isEmpty || libraryVM.isScanning)
                    
                    Spacer()
                    
                    Button(role: .destructive) {
                        libraryVM.clearLibraryAndCache()
                        playbackVM.clearQueueAndStop()
                    } label: {
                        Text("Clear Library Database")
                            .foregroundStyle(.red)
                    }
                }

                if libraryVM.isScanning {
                    LabeledContent("Scan Progress") {
                        ProgressView(value: libraryVM.scanProgress)
                            .frame(width: 150)
                    }
                }
                
                Toggle(isOn: $libraryVM.isFSEventsEnabled) {
                    HStack {
                        Text("Auto-Watch Folders for Changes (FSEvents)")
                        InfoButton(
                            title: "Auto-Watch Folders",
                            description: "Automatically watches your library folders for newly added or deleted FLAC files in the background using macOS FSEvents API.\n\nNote: If you have very large network drives, this may keep the drives awake."
                        )
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
    
    private var audioTab: some View {
        Form {
            Section("Audio Engine & Devices") {
                Picker("Output Device", selection: $selectedDeviceID) {
                    ForEach(outputDevices) { device in
                        Text(device.name).tag(String(device.id))
                    }
                }
                .onChange(of: selectedDeviceID) { newValue in
                    if let id = UInt32(newValue) {
                        halEngine.setOutputDevice(to: id)
                        hogModeEnabled = halEngine.isHogMode // refresh toggle
                    }
                }
                
                LabeledContent("Supported Sample Rates") {
                    Text(availableRates.map { "\(Int($0 / 1000))kHz" }.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                }

                // ISOLATED: Hog Mode & Bit-Perfect toggles read playbackVM.eqEnabled/crossfeedEnabled.
                // These live in AudioTabDSPControls (@ObservedObject) so only THEY re-render
                // on playback ticks — the rest of audioTab (and the Picker tab bar) stays stable.
                AudioTabDSPControls(
                    playbackVM: playbackVM,
                    halEngine: halEngine,
                    hogModeEnabled: $hogModeEnabled,
                    isBitPerfect: $isBitPerfect
                )

                Toggle(isOn: $isGaplessEnabled) {
                    HStack {
                        Text("Gapless Playback")
                        InfoButton(
                            title: "Gapless Playback",
                            description: "Seamlessly transitions between consecutive tracks by enqueueing the next track's buffer before the current one finishes.\n\nNote: For a perfectly seamless transition, the consecutive tracks must have the same sample rate."
                        )
                    }
                }
                
                Toggle(isOn: $allowDownsampling) {
                    HStack {
                        Text("Auto-Downsample Unsupported Hi-Res")
                        InfoButton(
                            title: "Auto-Downsample",
                            description: "If your DAC does not natively support a very high sample rate (like 192kHz or 176.4kHz), the engine will gracefully drop half the samples to play the file at exactly half the rate (96kHz or 88.2kHz) instead of failing to play.\n\nNote: This is an integer-ratio downsample, avoiding complex math artifacts."
                        )
                    }
                }
                
                Picker(selection: $replayGainMode) {
                    Text("Off").tag("off")
                    Text("Track Gain").tag("track")
                    Text("Album Gain").tag("album")
                } label: {
                    HStack {
                        Text("ReplayGain")
                        InfoButton(
                            title: "ReplayGain",
                            description: "Uses embedded REPLAYGAIN_TRACK_GAIN or REPLAYGAIN_ALBUM_GAIN tags (if present in the file's metadata) to normalize playback volume evenly across tracks or albums.\n\nNote: If a file does not contain these tags, it will play at its original volume."
                        )
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
    
    private var aboutTab: some View {
        ScrollView {
            VStack(spacing: 0) {
                
                // ── Hero ──────────────────────────────────────────────────
                ZStack {
                    LinearGradient(
                        colors: [
                            themeManager.accentColor.color.opacity(0.3),
                            themeManager.accentColor.color.opacity(0.05),
                            Color.clear
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 220)
                    
                    VStack(spacing: 14) {
                        if let icon = NSImage(named: "AppIcon") {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .shadow(color: themeManager.accentColor.color.opacity(0.5), radius: 20, x: 0, y: 8)
                        }
                        
                        VStack(spacing: 4) {
                            Text("YM Pro")
                                .font(.system(size: 26, weight: .black, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.primary, .primary.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            
                            Text("Version 2.2.2  ·  Build 14")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                    .padding(.top, 24)
                }
                
                // ── Tagline ───────────────────────────────────────────────
                Text("Bit-Perfect Audio. No Compromises.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                
                // ── Feature Cards ─────────────────────────────────────────
                VStack(spacing: 10) {
                    Text("What's Under the Hood")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        AboutFeatureCard(icon: "waveform",                         title: "CoreAudio HAL",    subtitle: "Direct hardware I/O",    accent: themeManager.accentColor.color)
                        AboutFeatureCard(icon: "music.note",                       title: "FLAC + ALAC",      subtitle: "Lossless decoding",        accent: themeManager.accentColor.color)
                        AboutFeatureCard(icon: "infinity",                         title: "Gapless Playback", subtitle: "Zero-gap transitions",     accent: themeManager.accentColor.color)
                        AboutFeatureCard(icon: "slider.horizontal.3",              title: "Parametric EQ",    subtitle: "10-band precision",        accent: themeManager.accentColor.color)
                        AboutFeatureCard(icon: "gauge.with.dots.needle.67percent", title: "ReplayGain",       subtitle: "Album & track gain",       accent: themeManager.accentColor.color)
                        AboutFeatureCard(icon: "sparkles",                         title: "Liquid Glass UI",  subtitle: "Native macOS design",      accent: themeManager.accentColor.color)
                    }
                    .padding(.horizontal, 16)
                }
                
                Divider()
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                
                // ── Tech Stack ────────────────────────────────────────────
                VStack(spacing: 10) {
                    Text("Technologies")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                    
                    HStack(spacing: 8) {
                        ForEach(["Swift 5", "SwiftUI", "CoreAudio", "GRDB", "libFLAC"], id: \.self) { tech in
                            Text(tech)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(themeManager.accentColor.color)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(themeManager.accentColor.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Divider()
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                
                // ── Feedback & Support ────────────────────────────────────
                HStack(spacing: 16) {
                    Button(action: {
                        if let url = URL(string: "macappstore://apps.apple.com/app/id6804453207?action=write-review") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "star.bubble.fill")
                            Text("Rate on the App Store")
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(themeManager.accentColor.color)
                    
                    Button(action: {
                        if let url = URL(string: "https://github.com/yoneshmurugan/YMProPlayer/issues/new") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "ladybug.fill")
                            Text("Report Bug / Feedback")
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.secondary)
                }
                
                Divider()
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                
                // ── Footer ────────────────────────────────────────────────
                VStack(spacing: 6) {
                    Text("Crafted with love ♥")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("© 2026 YM Pro. All rights reserved.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text("Made for audiophiles, by an audiophile.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.quaternary)
                        .padding(.top, 2)
                }
                .padding(.bottom, 28)
            }
        }
    }




}

// MARK: - DSP Controls (isolated @ObservedObject subscription)
// Hog Mode and Bit-Perfect toggles read playbackVM.eqEnabled / crossfeedEnabled.
// Wrapping them here means only this tiny view re-renders on every playback tick,
// not the entire SettingsView (which would flicker the tab bar Picker).
struct AudioTabDSPControls: View {
    let playbackVM: PlaybackViewModel
    let halEngine: CoreAudioHALEngine
    @Binding var hogModeEnabled: Bool
    @Binding var isBitPerfect: Bool

    var body: some View {
        let dspActive = playbackVM.eqEnabled || playbackVM.crossfeedEnabled

        Toggle(isOn: $hogModeEnabled) {
            HStack {
                Text("Hog Mode (Exclusive Access)")
                InfoButton(
                    title: "Hog Mode (Exclusive Access)",
                    description: "Grants the player exclusive access to the audio device hardware, preventing the macOS system mixer from intercepting or modifying the signal.\n\nWarning: When enabled, all other applications (YouTube, system alerts, etc.) will be muted and cannot use this audio device until Hog Mode is turned off. Some built-in devices (like MacBook speakers) may not support Hog Mode."
                )
            }
        }
        .disabled(dspActive)
        .grayscale(dspActive ? 1.0 : 0.0)
        .opacity(dspActive ? 0.5 : 1.0)
        .onChange(of: hogModeEnabled) { enabled in
            _ = halEngine.setHogModeSafe(enabled)
            DispatchQueue.main.async {
                hogModeEnabled = halEngine.isHogMode
            }
        }

        Toggle(isOn: $isBitPerfect) {
            HStack {
                Text("Bit-Perfect Mode")
                InfoButton(
                    title: "Bit-Perfect Mode",
                    description: "Bit-Perfect mode bypasses the software volume control, delivering the audio stream exactly as it was decoded (1:1) to your DAC without any mathematical alterations.\n\nUse this to ensure the highest possible fidelity. (Requires you to control volume via your external amplifier or DAC)."
                )
            }
        }
        .disabled(dspActive)
        .grayscale(dspActive ? 1.0 : 0.0)
        .opacity(dspActive ? 0.5 : 1.0)
        .onChange(of: isBitPerfect) { enabled in
            playbackVM.isBitPerfect = enabled
        }
    }
}

struct InfoButton: View {
    let title: String
    let description: String
    @State private var showingPopover = false
    
    var body: some View {
        Button {
            showingPopover.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .popover(isPresented: $showingPopover) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(width: 320)
        }
    }
}

// MARK: - About Feature Card

struct AboutFeatureCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent.opacity(0.2), lineWidth: 1)
        )
    }
}
