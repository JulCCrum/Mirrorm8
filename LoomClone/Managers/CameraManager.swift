import Foundation
import AVFoundation
import Combine
import CoreMedia

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var selectedCamera: AVCaptureDevice?
    @Published var isRunning = false
    @Published var permissionGranted = false
    @Published var errorMessage: String?

    private var captureSession: AVCaptureSession?
    private var currentInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let sessionQueue = DispatchQueue(label: "com.loomclone.camera.session", qos: .userInitiated)
    private let videoOutputQueue = DispatchQueue(label: "com.loomclone.camera.videooutput", qos: .userInitiated)

    override init() {
        super.init()
        checkPermission()
        setupDeviceDiscovery()
        setupNotifications()
    }

    private func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            refreshCameraList()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permissionGranted = granted
                    if granted { self?.refreshCameraList() }
                }
            }
        case .denied, .restricted:
            permissionGranted = false
            errorMessage = "Camera access denied. Please enable in System Settings."
        @unknown default:
            permissionGranted = false
        }
    }

    private func setupDeviceDiscovery() {
        NotificationCenter.default.addObserver(self, selector: #selector(deviceConnected), name: .AVCaptureDeviceWasConnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(deviceDisconnected), name: .AVCaptureDeviceWasDisconnected, object: nil)
    }

    private func setupNotifications() {
        // Handle session interruptions (e.g., phone call, other app using camera)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted), name: .AVCaptureSessionWasInterrupted, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded), name: .AVCaptureSessionInterruptionEnded, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError), name: .AVCaptureSessionRuntimeError, object: nil)
    }

    @objc private func deviceConnected(_ notification: Notification) { refreshCameraList() }
    @objc private func deviceDisconnected(_ notification: Notification) { refreshCameraList() }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        print("[Camera] Session interrupted")
        DispatchQueue.main.async { [weak self] in self?.isRunning = false }
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        print("[Camera] Session interruption ended, restarting...")
        sessionQueue.async { [weak self] in
            self?.captureSession?.startRunning()
            DispatchQueue.main.async { self?.isRunning = true }
        }
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError {
            print("[Camera] Runtime error: \(error.localizedDescription)")
            // Try to restart
            sessionQueue.async { [weak self] in
                self?.captureSession?.startRunning()
            }
        }
    }

    func refreshCameraList() {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macOS 14.0, *) { deviceTypes.append(.external) } else { deviceTypes.append(.externalUnknown) }
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: .unspecified)
        DispatchQueue.main.async { [weak self] in
            self?.availableCameras = discoverySession.devices
            if self?.selectedCamera == nil {
                self?.selectedCamera = discoverySession.devices.first { $0.localizedName.lowercased().contains("dji") || $0.localizedName.lowercased().contains("osmo") } ?? discoverySession.devices.first
            }
        }
    }

    func startSession() {
        guard permissionGranted else { return }
        sessionQueue.async { [weak self] in
            // If session already exists and is running, don't recreate
            if let session = self?.captureSession, session.isRunning {
                return
            }
            self?.setupCaptureSession()
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            DispatchQueue.main.async { self?.isRunning = false }
        }
    }

    private func setupCaptureSession() {
        // Stop existing session first
        captureSession?.stopRunning()

        let session = AVCaptureSession()
        session.beginConfiguration()

        // Use a preset that works well with most cameras including FaceTime
        session.sessionPreset = .medium

        guard let camera = selectedCamera else {
            DispatchQueue.main.async { [weak self] in self?.errorMessage = "No camera selected" }
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
                currentInput = input
            }
        } catch {
            DispatchQueue.main.async { [weak self] in self?.errorMessage = "Failed to setup camera: \(error.localizedDescription)" }
            return
        }

        // Add video data output to keep the capture pipeline active
        // This prevents FaceTime and other cameras from freezing
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: videoOutputQueue)

        if session.canAddOutput(output) {
            session.addOutput(output)
            self.videoOutput = output
            print("[Camera] Added video data output")
        }

        session.commitConfiguration()
        self.captureSession = session

        // Start session AFTER configuration is committed
        session.startRunning()

        DispatchQueue.main.async { [weak self] in
            self?.isRunning = session.isRunning
            print("[Camera] Session running: \(session.isRunning)")
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // We don't need to do anything with the frames for preview
        // But having this delegate keeps the pipeline active
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Frames are being dropped - this is fine for preview-only use
    }

    func switchCamera(to camera: AVCaptureDevice) {
        let previousCamera = selectedCamera
        selectedCamera = camera

        sessionQueue.async { [weak self] in
            guard let self = self, let session = self.captureSession else { return }

            // Stop the session before reconfiguring
            let wasRunning = session.isRunning
            if wasRunning {
                session.stopRunning()
            }

            session.beginConfiguration()

            // Remove current input
            if let currentInput = self.currentInput {
                session.removeInput(currentInput)
            }

            // Remove and re-add video output (some cameras need fresh output)
            if let oldOutput = self.videoOutput {
                session.removeOutput(oldOutput)
            }

            // Add new input
            do {
                let newInput = try AVCaptureDeviceInput(device: camera)
                if session.canAddInput(newInput) {
                    session.addInput(newInput)
                    self.currentInput = newInput
                } else {
                    throw NSError(domain: "CameraManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot add camera input"])
                }
            } catch {
                // Restore previous camera on failure
                DispatchQueue.main.async {
                    self.selectedCamera = previousCamera
                    self.errorMessage = "Failed to switch camera: \(error.localizedDescription)"
                }
                session.commitConfiguration()
                if wasRunning { session.startRunning() }
                return
            }

            // Re-add video output
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.setSampleBufferDelegate(self, queue: self.videoOutputQueue)

            if session.canAddOutput(output) {
                session.addOutput(output)
                self.videoOutput = output
            }

            session.commitConfiguration()

            // Restart if it was running
            if wasRunning {
                session.startRunning()
            }

            DispatchQueue.main.async {
                self.isRunning = session.isRunning
                print("[Camera] Switched to \(camera.localizedName), running: \(session.isRunning)")
            }
        }
    }

    func getCaptureSession() -> AVCaptureSession? { return captureSession }

    deinit {
        NotificationCenter.default.removeObserver(self)
        captureSession?.stopRunning()
    }
}
