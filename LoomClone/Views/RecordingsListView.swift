import SwiftUI
import AVKit

struct RecordingsListView: View {
    @EnvironmentObject var recordingsManager: RecordingsManager
    @State private var selectedRecording: Recording?
    @State private var showDeleteConfirmation = false
    @State private var recordingToDelete: Recording?
    @State private var searchText = ""

    var filteredRecordings: [Recording] {
        searchText.isEmpty ? recordingsManager.recordings : recordingsManager.recordings.filter { $0.filename.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack { Image(systemName: "magnifyingglass").foregroundColor(.secondary); TextField("Search...", text: $searchText).textFieldStyle(.plain) }
                    .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor))).frame(maxWidth: 200)
                Spacer()
                Button { recordingsManager.loadRecordings() } label: { Image(systemName: "arrow.clockwise") }
                Button { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: RecordingsManager.recordingsDirectory.path) } label: { Image(systemName: "folder") }
            }.padding()
            Divider()
            if recordingsManager.isLoading {
                Spacer(); ProgressView("Loading..."); Spacer()
            } else if filteredRecordings.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "video.slash").font(.system(size: 48)).foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "No recordings yet" : "No matches").font(.headline).foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List(selection: $selectedRecording) {
                    ForEach(filteredRecordings) { recording in
                        RecordingRow(recording: recording).tag(recording)
                            .contextMenu {
                                if recording.isAvailable {
                                    Button("Play") { recordingsManager.openRecording(recording) }
                                    Button("Show in Finder") { recordingsManager.openInFinder(recording) }
                                }
                                Divider()
                                Button("Delete", role: .destructive) { recordingToDelete = recording; showDeleteConfirmation = true }
                            }
                    }
                }.listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .confirmationDialog("Delete Recording?", isPresented: $showDeleteConfirmation, presenting: recordingToDelete) { r in
            Button("Delete", role: .destructive) { recordingsManager.deleteRecording(r) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Delete '\($0.filename)'? This cannot be undone.") }
        .onAppear { recordingsManager.loadRecordings() }
    }
}

struct RecordingRow: View {
    let recording: Recording
    @State private var thumbnail: NSImage?
    @EnvironmentObject var recordingsManager: RecordingsManager

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.black).frame(width: 80, height: 45)
                if let t = thumbnail { Image(nsImage: t).resizable().aspectRatio(contentMode: .fill).frame(width: 80, height: 45).clipShape(RoundedRectangle(cornerRadius: 8)) }
                else { Image(systemName: "video.fill").foregroundColor(.gray) }
                VStack { Spacer(); HStack { Spacer(); Text(recording.formattedDuration).font(.caption2).fontWeight(.medium).padding(4).background(Color.black.opacity(0.7)).foregroundColor(.white).cornerRadius(4).padding(4) } }.frame(width: 80, height: 45)
            }
            .opacity(recording.isAvailable ? 1 : 0.4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(recording.filename).font(.subheadline).fontWeight(.medium).lineLimit(1)
                    StorageBadge(location: recording.storageLocation, isAvailable: recording.isAvailable)
                }
                HStack(spacing: 8) {
                    Text(recording.formattedDate)
                    Text("•")
                    Text(recording.formattedFileSize)
                    if !recording.isAvailable {
                        Text("•")
                        Text("Unavailable").foregroundColor(.orange)
                    }
                }.font(.caption).foregroundColor(.secondary)
            }
            .opacity(recording.isAvailable ? 1 : 0.5)

            Spacer()
            if recording.isAvailable {
                HStack(spacing: 8) {
                    Button { recordingsManager.openRecording(recording) } label: { Image(systemName: "play.fill") }.buttonStyle(.borderless)
                    Button { recordingsManager.openInFinder(recording) } label: { Image(systemName: "folder") }.buttonStyle(.borderless)
                }
            } else {
                Image(systemName: "externaldrive.trianglebadge.exclamationmark")
                    .foregroundColor(.orange).help("External drive disconnected")
            }
        }.padding(.vertical, 8).task { thumbnail = await recordingsManager.generateThumbnail(for: recording) }
    }
}

struct StorageBadge: View {
    let location: String
    let isAvailable: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: location == "Internal" ? "internaldrive" : "externaldrive.fill")
                .font(.system(size: 8))
            Text(location)
                .font(.system(size: 9, weight: .medium))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(location == "Internal" ? Color.blue.opacity(0.15) : Color.orange.opacity(isAvailable ? 0.15 : 0.3))
        )
        .foregroundColor(location == "Internal" ? .blue : (isAvailable ? .orange : .red))
    }
}
