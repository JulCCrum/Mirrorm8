import SwiftUI
import AVFoundation
import AppKit

struct CameraPreviewView: NSViewRepresentable {
    @ObservedObject var cameraManager: CameraManager

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.cameraManager = cameraManager
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.updatePreviewLayer()
    }
}

class CameraPreviewNSView: NSView {
    var cameraManager: CameraManager?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var lastSession: AVCaptureSession?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }

    func updatePreviewLayer() {
        guard let cameraManager = cameraManager,
              let session = cameraManager.getCaptureSession() else { return }

        // Only recreate layer if session changed
        if session !== lastSession {
            previewLayer?.removeFromSuperlayer()

            let newLayer = AVCaptureVideoPreviewLayer(session: session)
            newLayer.frame = bounds
            newLayer.videoGravity = .resizeAspectFill

            if let rootLayer = layer {
                rootLayer.addSublayer(newLayer)
            }

            previewLayer = newLayer
            lastSession = session
        }

        previewLayer?.frame = bounds
    }
}
