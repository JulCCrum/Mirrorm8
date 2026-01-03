import SwiftUI
import ScreenCaptureKit
import AVFoundation

struct ControlPanelView: View {
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var screenCaptureManager: ScreenCaptureManager
    @EnvironmentObject var recordingCoordinator: RecordingCoordinator
    @EnvironmentObject var recordingsManager: RecordingsManager
    @State private var countdown: Int? = nil

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                if recordingCoordinator.isRecording {
                    HStack(spacing: 8) {
                        Circle().fill(Color.red).frame(width: 12, height: 12)
                        Text(recordingCoordinator.isPaused ? "Paused" : "Recording").font(.headline).foregroundColor(recordingCoordinator.isPaused ? .orange : .red)
                    }
                    Text(recordingCoordinator.formattedDuration).font(.system(size: 48, weight: .light, design: .monospaced))
                } else if let count = countdown {
                    Text("\(count)").font(.system(size: 72, weight: .bold)).foregroundColor(.accentColor)
                } else {
                    Text("Ready to Record").font(.headline).foregroundColor(.secondary)
                }
            }.frame(height: 100)

            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "display").foregroundColor(.secondary).frame(width: 24)
                    if screenCaptureManager.permissionGranted && !screenCaptureManager.availableDisplays.isEmpty {
                        Picker("Display", selection: Binding(get: { screenCaptureManager.selectedDisplay }, set: { screenCaptureManager.selectedDisplay = $0 })) {
                            ForEach(screenCaptureManager.availableDisplays, id: \.displayID) { display in
                                Text(screenCaptureManager.getDisplayName(for: display)).tag(display as SCDisplay?)
                            }
                        }.labelsHidden()
                    } else { Text(screenCaptureManager.permissionGranted ? "No displays" : "Permission required").foregroundColor(.secondary) }
                    Spacer()
                    if !screenCaptureManager.permissionGranted {
                        Button("Grant Access") { if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) } }.buttonStyle(.borderedProminent).controlSize(.small)
                        Button { Task { await screenCaptureManager.refreshDisplays() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                HStack {
                    Image(systemName: "video").foregroundColor(.secondary).frame(width: 24)
                    Picker("", selection: $cameraManager.selectedCamera) {
                        Text("No Camera").tag(nil as AVCaptureDevice?)
                        ForEach(cameraManager.availableCameras, id: \.uniqueID) { Text($0.localizedName).tag($0 as AVCaptureDevice?) }
                    }.labelsHidden().onChange(of: cameraManager.selectedCamera) { if let c = $0 { cameraManager.switchCamera(to: c) } }
                    Spacer()
                }
                HStack {
                    Image(systemName: "mic.fill").foregroundColor(.secondary).frame(width: 24)
                    Text("Microphone").foregroundColor(.secondary)
                    Spacer()
                    AudioLevelMeter(level: screenCaptureManager.audioLevel)
                        .frame(width: 100, height: 8)
                }
            }.padding().background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))

            HStack(spacing: 20) {
                if recordingCoordinator.isRecording {
                    Button { recordingCoordinator.togglePause() } label: { Image(systemName: recordingCoordinator.isPaused ? "play.fill" : "pause.fill").font(.title2).frame(width: 50, height: 50) }.buttonStyle(.bordered).controlSize(.large)
                    Button { Task { if let url = await recordingCoordinator.stopRecording() { recordingsManager.addRecording(from: url) } } } label: { Image(systemName: "stop.fill").font(.title).foregroundColor(.white).frame(width: 60, height: 60).background(Color.red).clipShape(Circle()) }.buttonStyle(.plain)
                } else {
                    Button { startRecordingWithCountdown() } label: { HStack { Image(systemName: "record.circle").font(.title2); Text("Start Recording").fontWeight(.semibold) }.foregroundColor(.white).padding(.horizontal, 24).padding(.vertical, 14).background(RoundedRectangle(cornerRadius: 12).fill(Color.red)) }.buttonStyle(.plain).disabled(!canStart).opacity(canStart ? 1 : 0.5).keyboardShortcut("r", modifiers: [.command])
                }
            }
            if let e = screenCaptureManager.errorMessage { Text(e).font(.caption).foregroundColor(.red) }
        }
    }

    private var canStart: Bool { screenCaptureManager.selectedDisplay != nil && screenCaptureManager.permissionGranted }

    private func startRecordingWithCountdown() {
        countdown = 3
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if let c = countdown, c > 1 { countdown = c - 1 } else { timer.invalidate(); countdown = nil; Task { await recordingCoordinator.startRecording() } }
        }
    }
}

struct AudioLevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                RoundedRectangle(cornerRadius: 4)
                    .fill(levelColor)
                    .frame(width: geo.size.width * CGFloat(level))
                    .animation(.easeOut(duration: 0.05), value: level)
            }
        }
    }

    private var levelColor: Color {
        if level > 0.8 { return .red }
        if level > 0.5 { return .yellow }
        return .green
    }
}
