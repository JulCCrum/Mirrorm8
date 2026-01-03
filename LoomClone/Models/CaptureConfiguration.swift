import Foundation
import ScreenCaptureKit
import AVFoundation

struct CaptureConfiguration {
    var selectedDisplay: SCDisplay?
    var selectedCamera: AVCaptureDevice?
    var selectedMicrophone: AVCaptureDevice?
    var captureSystemAudio: Bool = true
    var captureMicrophone: Bool = true
    var videoQuality: VideoQuality = .high
    var overlaySize: OverlaySize = .medium
    var overlayShape: OverlayShape = .circle

    enum VideoQuality: String, CaseIterable, Identifiable {
        case low = "720p", medium = "1080p", high = "4K"
        var id: String { rawValue }
        var resolution: CGSize {
            switch self {
            case .low: return CGSize(width: 1280, height: 720)
            case .medium: return CGSize(width: 1920, height: 1080)
            case .high: return CGSize(width: 3840, height: 2160)
            }
        }
        var bitrate: Int {
            switch self { case .low: return 5_000_000; case .medium: return 10_000_000; case .high: return 20_000_000 }
        }
    }

    enum OverlaySize: String, CaseIterable, Identifiable {
        case small = "Small", medium = "Medium", large = "Large"
        var id: String { rawValue }
        var diameter: CGFloat {
            switch self { case .small: return 150; case .medium: return 200; case .large: return 280 }
        }
    }

    enum OverlayShape: String, CaseIterable, Identifiable {
        case circle = "Circle", roundedRect = "Rounded Rectangle"
        var id: String { rawValue }
    }
}
