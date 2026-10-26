import SwiftUI
import AppKit
import AVFoundation

@MainActor
class CameraOverlayWindowController {
    static let shared = CameraOverlayWindowController()
    private var overlayWindow: NSPanel?
    private var cameraManager: CameraManager?
    private var previewView: OverlayCameraPreviewView?
    private var containerView: ShapedContainerView?
    private init() {}

    var currentShape: CaptureConfiguration.OverlayShape {
        let raw = UserDefaults.standard.string(forKey: "overlayShape") ?? CaptureConfiguration.OverlayShape.circle.rawValue
        return CaptureConfiguration.OverlayShape(rawValue: raw) ?? .circle
    }

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
        let shape = currentShape
        let savedWidth = UserDefaults.standard.double(forKey: "overlayWidth")
        let savedHeight = UserDefaults.standard.double(forKey: "overlayHeight")
        let width: CGFloat = savedWidth > 0 ? CGFloat(savedWidth) : shape.defaultSize.width
        let height: CGFloat = savedHeight > 0 ? CGFloat(savedHeight) : shape.defaultSize.height
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let frame = NSRect(x: screenFrame.maxX - width - 40, y: screenFrame.minY + 40, width: width, height: height)
        let panel = DraggablePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true

        let preview = OverlayCameraPreviewView(frame: NSRect(x: 0, y: 0, width: width, height: height), shape: shape)
        preview.autoresizingMask = [.width, .height]
        self.previewView = preview

        let container = ShapedContainerView(frame: NSRect(x: 0, y: 0, width: width, height: height), shape: shape)
        container.autoresizingMask = [.width, .height]
        container.setPreviewView(preview)

        panel.contentView = container
        self.overlayWindow = panel
        self.containerView = container
    }

    func updateShape(_ shape: CaptureConfiguration.OverlayShape) {
        UserDefaults.standard.set(shape.rawValue, forKey: "overlayShape")
        guard let window = overlayWindow else { return }

        // Update container and preview shapes
        containerView?.updateShape(shape)
        previewView?.updateShape(shape)

        // Resize window to default size for the new shape
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        let newSize = shape.defaultSize
        let newFrame = NSRect(
            x: center.x - newSize.width / 2,
            y: center.y - newSize.height / 2,
            width: newSize.width,
            height: newSize.height
        )
        window.setFrame(newFrame, display: true, animate: true)
        UserDefaults.standard.set(Double(newSize.width), forKey: "overlayWidth")
        UserDefaults.standard.set(Double(newSize.height), forKey: "overlayHeight")
    }

    func updateSize(_ size: CGFloat) {
        let shape = currentShape
        if shape == .circle {
            updateFrame(width: Double(size), height: Double(size))
        } else {
            guard let window = overlayWindow else { return }
            let aspect = window.frame.height / window.frame.width
            updateFrame(width: Double(size), height: Double(size * aspect))
        }
    }

    func updateFrame(width: Double, height: Double) {
        guard let window = overlayWindow else { return }
        let shape = currentShape
        let w = CGFloat(width)
        let h = shape == .circle ? w : CGFloat(height)
        var frame = window.frame
        frame.origin.x -= (w - frame.width) / 2
        frame.origin.y -= (h - frame.height) / 2
        frame.size = CGSize(width: w, height: h)
        window.setFrame(frame, display: true)
        UserDefaults.standard.set(Double(w), forKey: "overlayWidth")
        UserDefaults.standard.set(Double(h), forKey: "overlayHeight")
    }
}

class ShapedContainerView: NSView {
    private var contentClipView: NSView?
    private var borderLayer: CAShapeLayer?
    private var maskLayer: CAShapeLayer?
    private var shape: CaptureConfiguration.OverlayShape

    init(frame: NSRect, shape: CaptureConfiguration.OverlayShape) {
        self.shape = shape
        super.init(frame: frame)
        wantsLayer = true
        setupViews()
    }
    required init?(coder: NSCoder) {
        self.shape = .circle
        super.init(coder: coder)
        wantsLayer = true
        setupViews()
    }

    private func maskPath(for rect: CGRect) -> CGPath {
        switch shape {
        case .circle: return CGPath(ellipseIn: rect, transform: nil)
        case .roundedRect: return CGPath(roundedRect: rect, cornerWidth: shape.cornerRadius, cornerHeight: shape.cornerRadius, transform: nil)
        }
    }

    private func setupViews() {
        layer?.backgroundColor = NSColor.clear.cgColor

        let clip = NSView(frame: bounds)
        clip.wantsLayer = true
        clip.layer?.backgroundColor = NSColor.black.cgColor

        let clipMask = CAShapeLayer()
        clipMask.path = maskPath(for: bounds)
        clip.layer?.mask = clipMask
        self.maskLayer = clipMask

        clip.shadow = NSShadow()
        clip.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.5)
        clip.shadow?.shadowOffset = NSSize(width: 0, height: -4)
        clip.shadow?.shadowBlurRadius = 12

        addSubview(clip)
        self.contentClipView = clip

        let border = CAShapeLayer()
        border.path = maskPath(for: bounds.insetBy(dx: 1.5, dy: 1.5))
        border.fillColor = NSColor.clear.cgColor
        border.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        border.lineWidth = 3
        layer?.addSublayer(border)
        self.borderLayer = border
    }

    override func layout() {
        super.layout()
        contentClipView?.frame = bounds
        maskLayer?.path = maskPath(for: bounds)
        borderLayer?.path = maskPath(for: bounds.insetBy(dx: 1.5, dy: 1.5))
        borderLayer?.frame = bounds
    }

    func setPreviewView(_ preview: NSView) {
        preview.frame = contentClipView?.bounds ?? bounds
        contentClipView?.addSubview(preview)
    }

    func updateShape(_ newShape: CaptureConfiguration.OverlayShape) {
        shape = newShape
        maskLayer?.path = maskPath(for: bounds)
        borderLayer?.path = maskPath(for: bounds.insetBy(dx: 1.5, dy: 1.5))
    }
}

class OverlayCameraPreviewView: NSView {
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var maskLayer: CAShapeLayer?
    private var shape: CaptureConfiguration.OverlayShape

    init(frame: NSRect, shape: CaptureConfiguration.OverlayShape) {
        self.shape = shape
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        setupMask()
    }

    required init?(coder: NSCoder) {
        self.shape = .circle
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        setupMask()
    }

    private func maskPath(for rect: CGRect) -> CGPath {
        switch shape {
        case .circle: return CGPath(ellipseIn: rect, transform: nil)
        case .roundedRect: return CGPath(roundedRect: rect, cornerWidth: shape.cornerRadius, cornerHeight: shape.cornerRadius, transform: nil)
        }
    }

    private func setupMask() {
        let mask = CAShapeLayer()
        mask.path = maskPath(for: bounds)
        layer?.mask = mask
        self.maskLayer = mask
    }

    func connectToSession(_ session: AVCaptureSession) {
        previewLayer?.removeFromSuperlayer()
        let newLayer = AVCaptureVideoPreviewLayer(session: session)
        newLayer.videoGravity = .resizeAspectFill
        newLayer.frame = bounds
        if let rootLayer = layer {
            rootLayer.insertSublayer(newLayer, at: 0)
        }
        self.previewLayer = newLayer
        maskLayer?.path = maskPath(for: bounds)
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
        maskLayer?.path = maskPath(for: bounds)
    }

    func updateShape(_ newShape: CaptureConfiguration.OverlayShape) {
        shape = newShape
        maskLayer?.path = maskPath(for: bounds)
    }
}

class DraggablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private var initialMouse: NSPoint?
    private var initialOrigin: NSPoint?

    override func mouseDown(with e: NSEvent) {
        initialMouse = NSEvent.mouseLocation
        initialOrigin = frame.origin
    }

    override func mouseDragged(with e: NSEvent) {
        guard let im = initialMouse, let io = initialOrigin else { return }
        let cm = NSEvent.mouseLocation
        setFrameOrigin(NSPoint(x: io.x + cm.x - im.x, y: io.y + cm.y - im.y))
    }

    override func mouseUp(with event: NSEvent) {
        initialMouse = nil
        initialOrigin = nil
    }
}
