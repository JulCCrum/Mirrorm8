import Foundation
import ScreenCaptureKit
import Combine
import CoreGraphics
import CoreAudio
import AVFoundation
import QuartzCore  // CACurrentMediaTime

@MainActor
class ScreenCaptureManager: NSObject, ObservableObject {
    @Published var availableDisplays: [SCDisplay] = []
    @Published var selectedDisplay: SCDisplay?
    @Published var permissionGranted = false
    @Published var isCapturing = false
    @Published var errorMessage: String?
    @Published var audioLevel: Float = 0  // 0.0 to 1.0
    @Published var audioLevelHistory: [Float] = Array(repeating: 0, count: 20)

    private var stream: SCStream?
    private var streamOutput: CaptureStreamOutput?
    private var micMonitorEngine: AVAudioEngine?
    // Throttle audio-meter UI updates. The tap fires ~100/sec; pushing each one to
    // the main queue floods SwiftUI's update loop and trips view-graph asserts.
    private var lastMeterUpdate: CFTimeInterval = 0
    private static let meterUpdateInterval: CFTimeInterval = 1.0 / 30.0  // 30 Hz
    var frameHandler: ((CMSampleBuffer) -> Void)?
    var audioHandler: ((CMSampleBuffer) -> Void)?

    override init() {
        super.init()
        Task {
            await checkPermissionAndRefresh()
            startMicMonitor()
        }
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

    func startMicMonitor() {
        guard micMonitorEngine == nil else { return }
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        inputNode.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            guard let data = channelData, frameLength > 0 else { return }
            var sumOfSquares: Float = 0
            for i in 0..<frameLength { sumOfSquares += data[i] * data[i] }
            let rms = sqrt(sumOfSquares / Float(frameLength))
            let level = min(rms * 12, 1.0)
            // Throttle on the audio thread before hopping to main.
            let now = CACurrentMediaTime()
            guard let strongSelf = self,
                  now - strongSelf.lastMeterUpdate >= Self.meterUpdateInterval
            else { return }
            self?.lastMeterUpdate = now
            // Hop to main via GCD, not `Task { @MainActor }`. Spawning a Swift
            // Concurrency task from an AVAudioEngine tap (which runs on a CoreAudio
            // real-time thread) races the executor-introspection path and crashes
            // in swift_task_isCurrentExecutorWithFlagsImpl under load.
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.audioLevel = level
                self.audioLevelHistory.append(level)
                if self.audioLevelHistory.count > 20 {
                    self.audioLevelHistory.removeFirst()
                }
            }
        }
        do {
            try engine.start()
            micMonitorEngine = engine
        } catch {
            print("[MicMonitor] Failed to start: \(error)")
        }
    }

    func stopMicMonitor() {
        micMonitorEngine?.inputNode.removeTap(onBus: 0)
        micMonitorEngine?.stop()
        micMonitorEngine = nil
    }

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
        guard let data = dataPointer, length > 0 else { return nil }

        // Determine audio format from the sample buffer
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return nil }

        let rms: Double
        if asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            // Float32 samples (typical for ScreenCaptureKit microphone output)
            let sampleCount = length / MemoryLayout<Float32>.size
            guard sampleCount > 0 else { return nil }
            let sumOfSquares = data.withMemoryRebound(to: Float32.self, capacity: sampleCount) { ptr in
                var sum = 0.0
                for i in 0..<sampleCount { sum += Double(ptr[i]) * Double(ptr[i]) }
                return sum
            }
            rms = sqrt(sumOfSquares / Double(sampleCount))
        } else {
            // Int16 samples (fallback)
            let sampleCount = length / MemoryLayout<Int16>.size
            guard sampleCount > 0 else { return nil }
            let sumOfSquares = data.withMemoryRebound(to: Int16.self, capacity: sampleCount) { ptr in
                var sum = 0.0
                for i in 0..<sampleCount { sum += Double(ptr[i]) * Double(ptr[i]) }
                return sum
            }
            rms = sqrt(sumOfSquares / Double(sampleCount)) / 32768.0
        }

        let level = Float(rms)
        return min(level * 12, 1.0)  // Amplify for better visibility, cap at 1.0
    }
}
