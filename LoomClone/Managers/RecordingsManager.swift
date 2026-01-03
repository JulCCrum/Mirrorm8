import Foundation
import AVFoundation
import AppKit
import Combine

class RecordingsManager: ObservableObject {
    @Published var recordings: [Recording] = []
    @Published var isLoading = false

    static var recordingsDirectory: URL {
        FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!.appendingPathComponent("LoomClone", isDirectory: true)
    }

    init() { loadRecordings() }

    func loadRecordings() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let directory = Self.recordingsDirectory
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey], options: [.skipsHiddenFiles])
                let recordings = fileURLs.filter { ["mp4", "mov"].contains($0.pathExtension.lowercased()) }.compactMap { self.createRecording(from: $0) }.sorted { $0.createdAt > $1.createdAt }
                DispatchQueue.main.async { self.recordings = recordings; self.isLoading = false }
            } catch { print("Error loading recordings: \(error)"); DispatchQueue.main.async { self.isLoading = false } }
        }
    }

    private func createRecording(from url: URL) -> Recording? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let creationDate = attributes[.creationDate] as? Date ?? Date()
            let fileSize = attributes[.size] as? Int64 ?? 0
            let asset = AVURLAsset(url: url)
            let duration = CMTimeGetSeconds(asset.duration)
            return Recording(id: UUID(), filename: url.lastPathComponent, createdAt: creationDate, duration: duration.isNaN ? 0 : duration, fileSize: fileSize, thumbnailPath: nil)
        } catch { print("Error creating recording entry: \(error)"); return nil }
    }

    func addRecording(from url: URL) {
        if let recording = createRecording(from: url) { DispatchQueue.main.async { self.recordings.insert(recording, at: 0) } }
    }

    func deleteRecording(_ recording: Recording) {
        do { try FileManager.default.removeItem(at: recording.filePath); DispatchQueue.main.async { self.recordings.removeAll { $0.id == recording.id } } } catch { print("Error deleting recording: \(error)") }
    }

    func openInFinder(_ recording: Recording) { NSWorkspace.shared.selectFile(recording.filePath.path, inFileViewerRootedAtPath: "") }
    func openRecording(_ recording: Recording) { NSWorkspace.shared.open(recording.filePath) }

    func generateThumbnail(for recording: Recording) async -> NSImage? {
        let asset = AVURLAsset(url: recording.filePath)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 180)
        do { let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil); return NSImage(cgImage: cgImage, size: NSSize(width: 320, height: 180)) } catch { return nil }
    }
}
