import Foundation
import AVFoundation
import ScreenCaptureKit
import Combine

@MainActor
class RecordingCoordinator: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var errorMessage: String?

    private var cameraManager: CameraManager?
    private var screenCaptureManager: ScreenCaptureManager?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var recordingStartTime: CMTime?
    private var lastVideoTime: CMTime?
    private var durationTimer: Timer?
    private var currentOutputURL: URL?
    private let writerQueue = DispatchQueue(label: "com.loomclone.writer")

    func setup(cameraManager: CameraManager, screenCaptureManager: ScreenCaptureManager) {
        self.cameraManager = cameraManager
        self.screenCaptureManager = screenCaptureManager
        screenCaptureManager.frameHandler = { [weak self] sampleBuffer in self?.handleScreenFrame(sampleBuffer) }
    }

    func startRecording() async {
        guard !isRecording else { return }
        do {
            let filename = "Recording_\(Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))).mp4".replacingOccurrences(of: ":", with: "-")
            let outputURL = RecordingsManager.recordingsDirectory.appendingPathComponent(filename)
            currentOutputURL = outputURL
            try FileManager.default.createDirectory(at: RecordingsManager.recordingsDirectory, withIntermediateDirectories: true)
            try setupAssetWriter(outputURL: outputURL)
            try await screenCaptureManager?.startCapture()
            isRecording = true
            recordingDuration = 0
            durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in Task { @MainActor in self?.recordingDuration += 1 } }
        } catch { errorMessage = "Failed to start recording: \(error.localizedDescription)" }
    }

    func stopRecording() async -> URL? {
        guard isRecording else { return nil }
        isRecording = false
        durationTimer?.invalidate()
        durationTimer = nil
        await screenCaptureManager?.stopCapture()
        let outputURL = currentOutputURL
        await finishWriting()
        return outputURL
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused { durationTimer?.invalidate() }
        else { durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in Task { @MainActor in self?.recordingDuration += 1 } } }
    }

    private func setupAssetWriter(outputURL: URL) throws {
        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        guard let display = screenCaptureManager?.selectedDisplay else { throw RecordingError.noDisplaySelected }
        let width = Int(display.width) * 2
        let height = Int(display.height) * 2
        let videoSettings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height, AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 10_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel, AVVideoMaxKeyFrameIntervalKey: 60]]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        if writer.canAdd(videoInput) { writer.add(videoInput) }
        let audioSettings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128000]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true
        if writer.canAdd(audioInput) { writer.add(audioInput) }
        self.assetWriter = writer
        self.videoInput = videoInput
        self.audioInput = audioInput
        self.pixelBufferAdaptor = adaptor
        writer.startWriting()
    }

    private func handleScreenFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording, !isPaused else { return }
        writerQueue.async { [weak self] in
            guard let self = self, let writer = self.assetWriter, let videoInput = self.videoInput, let adaptor = self.pixelBufferAdaptor else { return }
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if self.recordingStartTime == nil { self.recordingStartTime = presentationTime; writer.startSession(atSourceTime: presentationTime) }
            guard videoInput.isReadyForMoreMediaData, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
            self.lastVideoTime = presentationTime
        }
    }

    private func finishWriting() async {
        await withCheckedContinuation { continuation in
            writerQueue.async { [weak self] in
                guard let writer = self?.assetWriter else { continuation.resume(); return }
                self?.videoInput?.markAsFinished()
                self?.audioInput?.markAsFinished()
                writer.finishWriting {
                    DispatchQueue.main.async {
                        self?.assetWriter = nil; self?.videoInput = nil; self?.audioInput = nil; self?.pixelBufferAdaptor = nil; self?.recordingStartTime = nil; self?.lastVideoTime = nil
                        continuation.resume()
                    }
                }
            }
        }
    }

    var formattedDuration: String { String(format: "%02d:%02d", Int(recordingDuration) / 60, Int(recordingDuration) % 60) }

    enum RecordingError: LocalizedError {
        case noDisplaySelected, writerSetupFailed
        var errorDescription: String? { switch self { case .noDisplaySelected: return "No display selected"; case .writerSetupFailed: return "Failed to setup video writer" } }
    }
}
