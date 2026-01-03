import SwiftUI
import ScreenCaptureKit

struct DisplayPickerView: View {
    @EnvironmentObject var screenCaptureManager: ScreenCaptureManager
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text("Select Display to Record").font(.headline)
            if screenCaptureManager.availableDisplays.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "display.trianglebadge.exclamationmark").font(.system(size: 48)).foregroundColor(.secondary)
                    Text("No displays available").foregroundColor(.secondary)
                    if !screenCaptureManager.permissionGranted {
                        Text("Screen recording permission required").font(.caption).foregroundColor(.red)
                        Button("Open System Settings") { if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) } }.buttonStyle(.borderedProminent)
                    }
                    Button("Refresh") { Task { await screenCaptureManager.refreshDisplays() } }
                }.padding()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(screenCaptureManager.availableDisplays, id: \.displayID) { display in
                            DisplayCard(display: display, isSelected: screenCaptureManager.selectedDisplay?.displayID == display.displayID, displayName: screenCaptureManager.getDisplayName(for: display)) { screenCaptureManager.selectedDisplay = display }
                        }
                    }.padding(.horizontal)
                }
            }
            HStack {
                Button("Cancel") { isPresented = false }.keyboardShortcut(.escape)
                Spacer()
                Button("Select") { isPresented = false }.keyboardShortcut(.return).buttonStyle(.borderedProminent).disabled(screenCaptureManager.selectedDisplay == nil)
            }.padding(.top)
        }.padding().frame(minWidth: 500, minHeight: 300)
    }
}

struct DisplayCard: View {
    let display: SCDisplay; let isSelected: Bool; let displayName: String; let onSelect: () -> Void
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.2)).frame(width: 160, height: 100)
                    .overlay(VStack { Image(systemName: display.displayID == CGMainDisplayID() ? "display" : "display.2").font(.system(size: 32)).foregroundColor(.secondary); Text("\(Int(display.width)) x \(Int(display.height))").font(.caption).foregroundColor(.secondary) })
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3))
                Text(displayName).font(.subheadline).fontWeight(isSelected ? .semibold : .regular)
                if isSelected { Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor) }
            }.padding().background(RoundedRectangle(cornerRadius: 12).fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear))
        }.buttonStyle(.plain)
    }
}
