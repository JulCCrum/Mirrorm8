import SwiftUI

@main
struct LoomCloneApp: App {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var screenCaptureManager = ScreenCaptureManager()
    @StateObject private var recordingCoordinator = RecordingCoordinator()
    @StateObject private var recordingsManager = RecordingsManager()

    @State private var showOverlay = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(cameraManager)
                .environmentObject(screenCaptureManager)
                .environmentObject(recordingCoordinator)
                .environmentObject(recordingsManager)
                .onAppear {
                    recordingCoordinator.setup(
                        cameraManager: cameraManager,
                        screenCaptureManager: screenCaptureManager
                    )
                    if showOverlay {
                        CameraOverlayWindowController.shared.showWindow(cameraManager: cameraManager)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Toggle Camera Overlay") {
                    showOverlay.toggle()
                    if showOverlay {
                        CameraOverlayWindowController.shared.showWindow(cameraManager: cameraManager)
                    } else {
                        CameraOverlayWindowController.shared.hideWindow()
                    }
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(cameraManager)
                .environmentObject(screenCaptureManager)
        }
    }
}
