import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var screenCaptureManager: ScreenCaptureManager
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
                Section("Storage") {
                    HStack { Text("Recordings Location"); Spacer(); Text(RecordingsManager.recordingsDirectory.path).foregroundColor(.secondary).lineLimit(1) }
                    Button("Open in Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: RecordingsManager.recordingsDirectory.path) }
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
        }.padding().frame(width: 500, height: 400)
    }
}
