import SwiftUI

struct ContentView: View {
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var screenCaptureManager: ScreenCaptureManager
    @EnvironmentObject var recordingCoordinator: RecordingCoordinator
    @EnvironmentObject var recordingsManager: RecordingsManager
    @State private var showDisplayPicker = false
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("LoomClone").font(.title2).fontWeight(.bold)
                Spacer()
                HStack(spacing: 12) {
                    Button { CameraOverlayWindowController.shared.toggleWindow() } label: { Image(systemName: cameraManager.isRunning ? "video.fill" : "video.slash.fill") }.help("Toggle Camera Overlay")
                    Button { showDisplayPicker = true } label: { Image(systemName: "display") }.help("Select Display")
                }
            }.padding().background(Color(nsColor: .windowBackgroundColor))
            Divider()
            TabView(selection: $selectedTab) {
                VStack(spacing: 24) { ControlPanelView().padding(.top, 20); Spacer() }.tabItem { Label("Record", systemImage: "record.circle") }.tag(0)
                RecordingsListView().tabItem { Label("Library", systemImage: "folder") }.tag(1)
            }.padding()
        }
        .frame(minWidth: 400, minHeight: 500)
        .sheet(isPresented: $showDisplayPicker) { DisplayPickerView(isPresented: $showDisplayPicker).environmentObject(screenCaptureManager) }
        .onAppear { Task { await screenCaptureManager.checkPermissionAndRefresh() } }
    }
}
