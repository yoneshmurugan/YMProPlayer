// SettingsView.swift
// ytsplayer

import SwiftUI
import CoreAudio

struct SettingsView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playbackVM: PlaybackViewModel
    let halEngine: CoreAudioHALEngine

    @State private var showFolderPicker = false
    @State private var hogModeEnabled   = false
    @State private var availableRates: [Double] = []
    @AppStorage("allowDownsampling") private var allowDownsampling = false
    @AppStorage("isGaplessEnabled") private var isGaplessEnabled = false
    @AppStorage("isBitPerfect") private var isBitPerfect = true
    @AppStorage("hogModeEnabled") private var savedHogModeEnabled = true
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
                
                Toggle(isOn: $hogModeEnabled) {
                    HStack {
                        Text("Hog Mode (Exclusive Access)")
                        InfoButton(
                            title: "Hog Mode (Exclusive Access)",
                            description: "Grants the player exclusive access to the audio device hardware, preventing the macOS system mixer from intercepting or modifying the signal.\n\nWarning: When enabled, all other applications (YouTube, system alerts, etc.) will be muted and cannot use this audio device until Hog Mode is turned off. Some built-in devices (like MacBook speakers) may not support Hog Mode."
                        )
                    }
                }
                .onChange(of: hogModeEnabled) { enabled in
                    _ = halEngine.setHogModeSafe(enabled)
                    DispatchQueue.main.async {
                        hogModeEnabled = halEngine.isHogMode // refresh toggle
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
                .onChange(of: isBitPerfect) { enabled in
                    playbackVM.isBitPerfect = enabled
                }

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
        Form {
            Section("About") {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Build", value: "BitPerfect·FLAC·CoreAudio HAL")
            }
        }
        .formStyle(.grouped)
    }

    private func deviceName(for deviceID: AudioObjectID) -> String {
        guard deviceID != AudioObjectID(kAudioObjectUnknown) else { return "Unknown" }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &name)
        return name as String
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
