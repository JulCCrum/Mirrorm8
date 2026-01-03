# Mirrorm8

A native macOS screen recording app with a floating circular camera overlay, similar to Loom. Built with SwiftUI and leveraging ScreenCaptureKit for high-quality screen capture.

## Features

- **Screen Recording** - Capture your entire screen using ScreenCaptureKit
- **Floating Camera Bubble** - Circular, draggable camera overlay that stays on top
- **Multiple Camera Support** - Works with built-in FaceTime camera, external webcams, and DJI Osmo Pocket 3
- **External Display Support** - Choose which display to record
- **System Audio Capture** - Records system audio along with video
- **Recording Management** - View and manage your recordings

## Requirements

- macOS 13.0 or later
- Xcode 15.0 or later

## Permissions

The app requires the following permissions:
- **Screen Recording** - To capture your screen
- **Camera** - For the camera overlay

After granting permissions, you may need to quit and relaunch the app for them to take effect.

## Building

1. Clone the repository
2. Open `LoomClone.xcodeproj` in Xcode
3. Build and run (Cmd + R)

## Usage

1. Launch the app
2. Grant screen recording and camera permissions when prompted
3. Select your display and camera from the dropdown menus
4. Click "Start Recording" to begin
5. The circular camera overlay can be dragged anywhere on screen
6. Click "Stop Recording" to finish
7. Recordings are saved to `~/Movies/LoomClone/`

## Architecture

- **CameraManager** - Handles camera discovery, permissions, and AVCaptureSession management
- **ScreenCaptureManager** - Manages screen capture using ScreenCaptureKit
- **RecordingCoordinator** - Coordinates screen and camera recording into a single output
- **CameraOverlayWindow** - Floating circular camera preview window

## License

MIT License - see [LICENSE](LICENSE) for details.
