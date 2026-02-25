import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var screenCaptureManager: ScreenCaptureManager
    @EnvironmentObject var recordingsManager: RecordingsManager
    @AppStorage("overlaySize") private var overlaySize = CaptureConfiguration.OverlaySize.medium.rawValue
    @AppStorage("videoQuality") private var videoQuality = CaptureConfiguration.VideoQuality.high.rawValue

    var body: some View {
        TabView {
            Form {
                Section("Recording") {
                    Picker("Video Quality", selection: $videoQuality) {
                        ForEach(CaptureConfiguration.VideoQuality.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                }
                Section("Save Location") {
                    Picker("Save to", selection: Binding(
                        get: { recordingsManager.saveLocationPath },
                        set: { recordingsManager.saveLocationPath = $0; recordingsManager.loadRecordings() }
                    )) {
                        Text("Default (~/Movies/LoomClone)").tag("")
                        ForEach(recordingsManager.externalVolumes, id: \.path) { volume in
                            HStack {
                                Image(systemName: "externaldrive.fill")
                                Text(recordingsManager.volumeName(for: volume))
                            }.tag(volume.path)
                        }
                    }

                    if !recordingsManager.saveLocationPath.isEmpty && !recordingsManager.isSaveLocationAvailable {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                            Text("Selected drive is not connected. Recordings will save to default location.")
                                .font(.caption).foregroundColor(.orange)
                        }
                    }

                    HStack {
                        Text("Active location")
                        Spacer()
                        Text(recordingsManager.activeSaveDirectory.path)
                            .foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                    }

                    Button("Open in Finder") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: recordingsManager.activeSaveDirectory.path)
                    }

                    Button("Refresh Drives") {
                        recordingsManager.refreshExternalVolumes()
                    }
                }
            }.tabItem { Label("General", systemImage: "gear") }

            Form {
                Section("Camera") {
                    Picker("Default Camera", selection: $cameraManager.selectedCamera) {
                        Text("None").tag(nil as AVCaptureDevice?)
                        ForEach(cameraManager.availableCameras, id: \.uniqueID) { Text($0.localizedName).tag($0 as AVCaptureDevice?) }
                    }
                    Button("Refresh Camera List") { cameraManager.refreshCameraList() }
                }
                Section("Overlay") {
                    Picker("Size", selection: $overlaySize) {
                        ForEach(CaptureConfiguration.OverlaySize.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }.onChange(of: overlaySize) { if let s = CaptureConfiguration.OverlaySize(rawValue: $0) { CameraOverlayWindowController.shared.updateSize(s.diameter) } }
                }
                Section("Permissions") {
                    HStack { Text("Camera"); Spacer(); Image(systemName: cameraManager.permissionGranted ? "checkmark.circle.fill" : "xmark.circle").foregroundColor(cameraManager.permissionGranted ? .green : .red) }
                    HStack { Text("Screen Recording"); Spacer(); Image(systemName: screenCaptureManager.permissionGranted ? "checkmark.circle.fill" : "xmark.circle").foregroundColor(screenCaptureManager.permissionGranted ? .green : .red) }
                }
            }.tabItem { Label("Camera", systemImage: "video") }
        }.padding().frame(width: 500, height: 450)
    }
}
