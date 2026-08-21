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
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
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
            }

            Section("Audio Device") {
                LabeledContent("Output Device") {
                    Text(deviceName(for: halEngine.currentDeviceID))
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Supported Sample Rates") {
                    Text(availableRates.map { "\(Int($0 / 1000))kHz" }.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                }

                Toggle("Hog Mode (Exclusive Access)", isOn: $hogModeEnabled)
                    .onChange(of: hogModeEnabled) { enabled in
                        hogModeEnabled = halEngine.setHogModeSafe(enabled)
                    }
                    .help("Grants the app exclusive access to the audio device, preventing the macOS mixer from intercepting the signal.")

                Toggle("Auto-Downsample Unsupported Hi-Res Tracks", isOn: $allowDownsampling)
                    .help("If your DAC does not support 192kHz or 176.4kHz, this seamlessly drops half the samples to play perfectly at 96kHz/88.2kHz instead of failing.")
            }

            Section("About") {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Build", value: "BitPerfect·FLAC·CoreAudio HAL")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            hogModeEnabled  = halEngine.isHogMode
            availableRates  = halEngine.availableSampleRates()

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
