import SwiftUI
import ScreenCaptureKit
import AVFoundation

struct ControlPanelView: View {
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var screenCaptureManager: ScreenCaptureManager
    @EnvironmentObject var recordingCoordinator: RecordingCoordinator
    @EnvironmentObject var recordingsManager: RecordingsManager
    @State private var countdown: Int? = nil
    @AppStorage("overlayShape") private var overlayShape = CaptureConfiguration.OverlayShape.circle.rawValue
    @AppStorage("overlayWidth") private var overlayWidth: Double = 200
    @AppStorage("overlayHeight") private var overlayHeight: Double = 200

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
                    // TEMP DISABLED for crash bisection - see if launch crash goes away
                    // AudioWaveformView(levels: screenCaptureManager.audioLevelHistory)
                    //     .frame(width: 160, height: 30)
                    Color.clear.frame(width: 160, height: 30)
                }
            }.padding().background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))

            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "person.crop.rectangle").foregroundColor(.secondary).frame(width: 24)
                    Text("Overlay").foregroundColor(.secondary)
                    Spacer()
                    Picker("", selection: $overlayShape) {
                        ForEach(CaptureConfiguration.OverlayShape.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }.labelsHidden().frame(width: 160)
                    .onChange(of: overlayShape) {
                        if let s = CaptureConfiguration.OverlayShape(rawValue: $0) {
                            CameraOverlayWindowController.shared.updateShape(s)
                            overlayWidth = s.defaultSize.width
                            overlayHeight = s.defaultSize.height
                        }
                    }
                }
                HStack {
                    Text("Width").foregroundColor(.secondary).frame(width: 45, alignment: .leading)
                    Slider(value: $overlayWidth, in: 100...600)
                    Text("\(Int(overlayWidth))").foregroundColor(.secondary).frame(width: 35)
                }.onChange(of: overlayWidth) { _ in
                    CameraOverlayWindowController.shared.updateFrame(width: overlayWidth, height: overlayHeight)
                }
                if CaptureConfiguration.OverlayShape(rawValue: overlayShape) == .roundedRect {
                    HStack {
                        Text("Height").foregroundColor(.secondary).frame(width: 45, alignment: .leading)
                        Slider(value: $overlayHeight, in: 100...900)
                        Text("\(Int(overlayHeight))").foregroundColor(.secondary).frame(width: 35)
                    }.onChange(of: overlayHeight) { _ in
                        CameraOverlayWindowController.shared.updateFrame(width: overlayWidth, height: overlayHeight)
                    }
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

struct AudioWaveformView: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(for: level))
                    .frame(width: 6, height: max(3, CGFloat(level) * 28))
                    .animation(.linear(duration: 0.02), value: level)
            }
        }
    }

    private func barColor(for level: Float) -> Color {
        if level > 0.8 { return .red }
        if level > 0.5 { return .yellow }
        return .green
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
