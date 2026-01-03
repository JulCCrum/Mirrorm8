import Foundation
import ScreenCaptureKit
import Combine
import CoreGraphics

@MainActor
class ScreenCaptureManager: NSObject, ObservableObject {
    @Published var availableDisplays: [SCDisplay] = []
    @Published var selectedDisplay: SCDisplay?
    @Published var permissionGranted = false
    @Published var isCapturing = false
    @Published var errorMessage: String?
    @Published var audioLevel: Float = 0  // 0.0 to 1.0

    private var stream: SCStream?
    private var streamOutput: CaptureStreamOutput?
    var frameHandler: ((CMSampleBuffer) -> Void)?
    var audioHandler: ((CMSampleBuffer) -> Void)?

    override init() {
        super.init()
        Task { await checkPermissionAndRefresh() }
    }

    func checkPermissionAndRefresh() async {
        errorMessage = nil
        let hasAccess = CGPreflightScreenCaptureAccess()
        print("[ScreenCapture] CGPreflightScreenCaptureAccess: \(hasAccess)")

        // Try to get shareable content - this is the real test
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            permissionGranted = true
            availableDisplays = content.displays
            errorMessage = nil
            if selectedDisplay == nil { selectedDisplay = content.displays.first }
            print("[ScreenCapture] SUCCESS! Found \(content.displays.count) displays.")
        } catch {
            let nsError = error as NSError
            print("[ScreenCapture] SCShareableContent FAILED: \(nsError.domain) code=\(nsError.code)")
            print("[ScreenCapture] Error details: \(error.localizedDescription)")

            permissionGranted = false

            // SCContentSharingPickerError code -3801 = user denied
            // SCContentSharingPickerError code -3802 = not authorized
            if nsError.code == -3801 || nsError.code == -3802 || !hasAccess {
                errorMessage = "Screen recording not authorized. Grant access in System Settings, then QUIT (Cmd+Q) and relaunch."
            } else {
                // Permission might be granted but process wasn't authorized at launch
                errorMessage = "TCC permission check passed but ScreenCaptureKit failed. You MUST fully QUIT (Cmd+Q) and relaunch the app."
            }
        }
    }

    func refreshDisplays() async { await checkPermissionAndRefresh() }

    func startCapture(excludingWindows: [SCWindow] = []) async throws {
        guard let display = selectedDisplay else { throw CaptureError.noDisplaySelected }
        _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let filter = SCContentFilter(display: display, excludingWindows: excludingWindows)
        let config = SCStreamConfiguration()
        config.width = Int(display.width) * 2
        config.height = Int(display.height) * 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 5
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        config.capturesAudio = false  // Disabled - only using microphone
        if #available(macOS 15.0, *) {
            config.captureMicrophone = true
        }
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        let output = CaptureStreamOutput()
        output.frameHandler = frameHandler
        output.audioHandler = audioHandler
        output.audioLevelHandler = { [weak self] level in
            Task { @MainActor in self?.audioLevel = level }
        }
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.loomclone.screen.output"))
        // Only microphone audio (no system audio)
        if #available(macOS 15.0, *) {
            try stream.addStreamOutput(output, type: .microphone, sampleHandlerQueue: DispatchQueue(label: "com.loomclone.mic.output"))
        }
        self.streamOutput = output
        self.stream = stream
        try await stream.startCapture()
        isCapturing = true
    }

    func stopCapture() async {
        guard let stream = stream else { return }
        do { try await stream.stopCapture() } catch { print("Error stopping capture: \(error)") }
        self.stream = nil
        self.streamOutput = nil
        isCapturing = false
    }

    func getDisplayName(for display: SCDisplay) -> String {
        display.displayID == CGMainDisplayID() ? "Main Display" : "Display \(display.displayID)"
    }

    enum CaptureError: LocalizedError {
        case noDisplaySelected, permissionDenied
        var errorDescription: String? {
            switch self {
            case .noDisplaySelected: return "No display selected for capture"
            case .permissionDenied: return "Screen recording permission denied"
            }
        }
    }
}

class CaptureStreamOutput: NSObject, SCStreamOutput {
    var frameHandler: ((CMSampleBuffer) -> Void)?
    var audioHandler: ((CMSampleBuffer) -> Void)?
    var audioLevelHandler: ((Float) -> Void)?
    private var micCount = 0

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen: frameHandler?(sampleBuffer)
        case .microphone:
            micCount += 1
            if micCount % 100 == 1 { print("[Stream] Microphone sample #\(micCount)") }
            audioHandler?(sampleBuffer)
            // Calculate audio level for meter
            if let level = calculateAudioLevel(from: sampleBuffer) {
                audioLevelHandler?(level)
            }
        case .audio: break  // System audio disabled
        @unknown default: break
        }
    }

    private func calculateAudioLevel(from sampleBuffer: CMSampleBuffer) -> Float? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        guard let data = dataPointer else { return nil }

        // Calculate RMS (root mean square) of audio samples
        let samples = data.withMemoryRebound(to: Int16.self, capacity: length / 2) { ptr in
            Array(UnsafeBufferPointer(start: ptr, count: length / 2))
        }
        guard !samples.isEmpty else { return nil }

        let sumOfSquares = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        let rms = sqrt(sumOfSquares / Double(samples.count))
        let level = Float(rms / 32768.0)  // Normalize to 0-1
        return min(level * 3, 1.0)  // Amplify for better visibility, cap at 1.0
    }
}
