import SwiftUI
import AppKit
import AVFoundation

class CameraOverlayWindowController {
    static let shared = CameraOverlayWindowController()
    private var overlayWindow: NSPanel?
    private var cameraManager: CameraManager?
    private var previewView: OverlayCameraPreviewView?
    private init() {}

    func showWindow(cameraManager: CameraManager) {
        self.cameraManager = cameraManager
        if overlayWindow == nil { createWindow() }
        overlayWindow?.orderFront(nil)
        cameraManager.startSession()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.connectPreview() }
    }

    private func connectPreview() {
        guard let session = cameraManager?.getCaptureSession() else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.connectPreview() }
            return
        }
        previewView?.connectToSession(session)
    }

    func hideWindow() { overlayWindow?.orderOut(nil); cameraManager?.stopSession() }

    func toggleWindow() {
        if overlayWindow?.isVisible == true { hideWindow() }
        else if let manager = cameraManager { showWindow(cameraManager: manager) }
    }

    private func createWindow() {
        let savedDiameter = UserDefaults.standard.double(forKey: "customOverlayDiameter")
        let size: CGFloat = savedDiameter > 0 ? CGFloat(savedDiameter) : 200
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let frame = NSRect(x: screenFrame.maxX - size - 40, y: screenFrame.minY + 40, width: size, height: size)
        let panel = DraggablePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true

        let preview = OverlayCameraPreviewView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        preview.autoresizingMask = [.width, .height]
        self.previewView = preview

        let container = CircularContainerView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        container.autoresizingMask = [.width, .height]
        container.setPreviewView(preview)

        panel.contentView = container
        self.overlayWindow = panel
    }

    func updateSize(_ size: CGFloat) {
        guard let window = overlayWindow else { return }
        var frame = window.frame; let delta = size - frame.size.width
        frame.size = CGSize(width: size, height: size); frame.origin.x -= delta / 2; frame.origin.y -= delta / 2
        window.setFrame(frame, display: true, animate: true)
    }
}

class CircularContainerView: NSView {
    private var contentClipView: NSView?
    private var borderLayer: CAShapeLayer?
    private var maskLayer: CAShapeLayer?

    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; setupViews() }
    required init?(coder: NSCoder) { super.init(coder: coder); wantsLayer = true; setupViews() }

    private func setupViews() {
        layer?.backgroundColor = NSColor.clear.cgColor

        let clip = NSView(frame: bounds)
        clip.wantsLayer = true
        clip.layer?.backgroundColor = NSColor.black.cgColor

        // Create mask once and reuse
        let clipMask = CAShapeLayer()
        clipMask.path = CGPath(ellipseIn: bounds, transform: nil)
        clip.layer?.mask = clipMask
        self.maskLayer = clipMask

        clip.shadow = NSShadow()
        clip.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.5)
        clip.shadow?.shadowOffset = NSSize(width: 0, height: -4)
        clip.shadow?.shadowBlurRadius = 12

        addSubview(clip)
        self.contentClipView = clip

        let border = CAShapeLayer()
        border.path = CGPath(ellipseIn: bounds.insetBy(dx: 1.5, dy: 1.5), transform: nil)
        border.fillColor = NSColor.clear.cgColor
        border.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        border.lineWidth = 3
        layer?.addSublayer(border)
        self.borderLayer = border
    }

    override func layout() {
        super.layout()
        contentClipView?.frame = bounds
        // Update existing mask path instead of creating new mask
        maskLayer?.path = CGPath(ellipseIn: bounds, transform: nil)
        borderLayer?.path = CGPath(ellipseIn: bounds.insetBy(dx: 1.5, dy: 1.5), transform: nil)
        borderLayer?.frame = bounds
    }

    func setPreviewView(_ preview: NSView) {
        preview.frame = contentClipView?.bounds ?? bounds
        contentClipView?.addSubview(preview)
    }
}

class OverlayCameraPreviewView: NSView {
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var maskLayer: CAShapeLayer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        setupMask()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        setupMask()
    }

    private func setupMask() {
        let mask = CAShapeLayer()
        mask.path = CGPath(ellipseIn: bounds, transform: nil)
        layer?.mask = mask
        self.maskLayer = mask
    }

    func connectToSession(_ session: AVCaptureSession) {
        // Remove old layer
        previewLayer?.removeFromSuperlayer()

        // Create new preview layer
        let newLayer = AVCaptureVideoPreviewLayer(session: session)
        newLayer.videoGravity = .resizeAspectFill
        newLayer.frame = bounds

        // Insert below mask effects
        if let rootLayer = layer {
            rootLayer.insertSublayer(newLayer, at: 0)
        }

        self.previewLayer = newLayer

        // Update mask path
        maskLayer?.path = CGPath(ellipseIn: bounds, transform: nil)
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
        // Only update path, don't recreate mask
        maskLayer?.path = CGPath(ellipseIn: bounds, transform: nil)
    }
}

class DraggablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private var initialMouse: NSPoint?
    private var initialOrigin: NSPoint?
    private var isResizing = false
    private var initialDiameter: CGFloat = 0
    private var initialCenter: NSPoint = .zero

    @AppStorage("customOverlayDiameter") private var savedDiameter: Double = 200

    private static let edgeThreshold: CGFloat = 15
    private static let minDiameter: CGFloat = 100
    private static let maxDiameter: CGFloat = 500

    private var circleCenter: NSPoint {
        NSPoint(x: frame.origin.x + frame.width / 2, y: frame.origin.y + frame.height / 2)
    }

    private func isNearEdge(_ screenPoint: NSPoint) -> Bool {
        let center = circleCenter
        let radius = frame.width / 2
        let dx = screenPoint.x - center.x
        let dy = screenPoint.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        return abs(distance - radius) < Self.edgeThreshold
    }

    override func mouseMoved(with event: NSEvent) {
        let mouseLocation = NSEvent.mouseLocation
        if isNearEdge(mouseLocation) {
            NSCursor.resizeUpDown.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseDown(with e: NSEvent) {
        let mouseLocation = NSEvent.mouseLocation
        initialMouse = mouseLocation
        initialOrigin = frame.origin

        if isNearEdge(mouseLocation) {
            isResizing = true
            initialDiameter = frame.width
            initialCenter = circleCenter
        } else {
            isResizing = false
        }
    }

    override func mouseDragged(with e: NSEvent) {
        guard let im = initialMouse else { return }
        let cm = NSEvent.mouseLocation

        if isResizing {
            // Calculate distance from initial center to current mouse
            let dx = cm.x - initialCenter.x
            let dy = cm.y - initialCenter.y
            let currentDistance = sqrt(dx * dx + dy * dy)

            // Calculate distance from initial center to initial mouse
            let idx = im.x - initialCenter.x
            let idy = im.y - initialCenter.y
            let initialDistance = sqrt(idx * idx + idy * idy)

            // Scale diameter based on ratio of distances
            let scale = initialDistance > 0 ? currentDistance / initialDistance : 1
            let newDiameter = min(max(initialDiameter * scale, Self.minDiameter), Self.maxDiameter)

            // Keep centered
            let newOrigin = NSPoint(
                x: initialCenter.x - newDiameter / 2,
                y: initialCenter.y - newDiameter / 2
            )
            let newFrame = NSRect(x: newOrigin.x, y: newOrigin.y, width: newDiameter, height: newDiameter)
            setFrame(newFrame, display: true)
            savedDiameter = Double(newDiameter)
        } else {
            guard let io = initialOrigin else { return }
            setFrameOrigin(NSPoint(x: io.x + cm.x - im.x, y: io.y + cm.y - im.y))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isResizing {
            savedDiameter = Double(frame.width)
        }
        isResizing = false
        initialMouse = nil
        initialOrigin = nil
    }

    func applySavedDiameter() {
        let diameter = CGFloat(savedDiameter)
        if diameter != frame.width {
            CameraOverlayWindowController.shared.updateSize(diameter)
        }
    }
}
