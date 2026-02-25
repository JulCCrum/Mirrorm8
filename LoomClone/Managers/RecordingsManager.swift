import Foundation
import AVFoundation
import AppKit
import Combine

class RecordingsManager: ObservableObject {
    @Published var recordings: [Recording] = []
    @Published var isLoading = false
    @Published var externalVolumes: [URL] = []

    private var volumeObservers: [NSObjectProtocol] = []

    static var recordingsDirectory: URL {
        FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!.appendingPathComponent("LoomClone", isDirectory: true)
    }

    var saveLocationPath: String {
        get { UserDefaults.standard.string(forKey: "saveLocationPath") ?? "" }
        set {
            UserDefaults.standard.set(newValue, forKey: "saveLocationPath")
            objectWillChange.send()
        }
    }

    var activeSaveDirectory: URL {
        if !saveLocationPath.isEmpty {
            let url = URL(fileURLWithPath: saveLocationPath)
            if FileManager.default.fileExists(atPath: url.path) {
                return url.appendingPathComponent("LoomClone", isDirectory: true)
            }
        }
        return Self.recordingsDirectory
    }

    init() {
        refreshExternalVolumes()
        startVolumeMonitoring()
        loadRecordings()
    }

    deinit {
        for observer in volumeObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - Volume Detection

    func refreshExternalVolumes() {
        let keys: [URLResourceKey] = [.volumeIsRemovableKey, .volumeIsInternalKey, .volumeNameKey]
        guard let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else {
            externalVolumes = []
            return
        }

        externalVolumes = volumes.filter { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return false }
            let isRemovable = values.volumeIsRemovable ?? false
            let isInternal = values.volumeIsInternal ?? true
            return isRemovable || !isInternal
        }
    }

    private func startVolumeMonitoring() {
        let mountObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshExternalVolumes()
            self?.loadRecordings()
        }

        let unmountObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshExternalVolumes()
            self?.loadRecordings()
        }

        volumeObservers = [mountObserver, unmountObserver]
    }

    func volumeName(for url: URL) -> String {
        (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? url.lastPathComponent
    }

    var isSaveLocationAvailable: Bool {
        if saveLocationPath.isEmpty { return true }
        return FileManager.default.fileExists(atPath: saveLocationPath)
    }

    // MARK: - Recordings

    func loadRecordings() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var allRecordings: [Recording] = []

            // Load from default directory
            let defaultDir = Self.recordingsDirectory
            allRecordings += self.loadRecordingsFromDirectory(defaultDir, storageLocation: "Internal")

            // Load from external save location if configured
            if !self.saveLocationPath.isEmpty {
                let externalDir = URL(fileURLWithPath: self.saveLocationPath).appendingPathComponent("LoomClone", isDirectory: true)
                if externalDir != defaultDir && FileManager.default.fileExists(atPath: externalDir.path) {
                    let volumeName = self.volumeName(for: URL(fileURLWithPath: self.saveLocationPath))
                    allRecordings += self.loadRecordingsFromDirectory(externalDir, storageLocation: volumeName)
                }
            }

            allRecordings.sort { $0.createdAt > $1.createdAt }
            DispatchQueue.main.async { self.recordings = allRecordings; self.isLoading = false }
        }
    }

    private func loadRecordingsFromDirectory(_ directory: URL, storageLocation: String) -> [Recording] {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey], options: [.skipsHiddenFiles])
            return fileURLs
                .filter { ["mp4", "mov"].contains($0.pathExtension.lowercased()) }
                .compactMap { createRecording(from: $0, sourceDirectory: directory, storageLocation: storageLocation) }
        } catch {
            print("Error loading recordings from \(directory.path): \(error)")
            return []
        }
    }

    private func createRecording(from url: URL, sourceDirectory: URL? = nil, storageLocation: String = "Internal") -> Recording? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let creationDate = attributes[.creationDate] as? Date ?? Date()
            let fileSize = attributes[.size] as? Int64 ?? 0
            let asset = AVURLAsset(url: url)
            let duration = CMTimeGetSeconds(asset.duration)
            return Recording(
                id: UUID(),
                filename: url.lastPathComponent,
                createdAt: creationDate,
                duration: duration.isNaN ? 0 : duration,
                fileSize: fileSize,
                thumbnailPath: nil,
                sourceDirectory: sourceDirectory,
                storageLocation: storageLocation
            )
        } catch {
            print("Error creating recording entry: \(error)")
            return nil
        }
    }

    func addRecording(from url: URL) {
        let sourceDir = url.deletingLastPathComponent()
        let storageLocation: String
        if sourceDir == Self.recordingsDirectory {
            storageLocation = "Internal"
        } else {
            storageLocation = volumeName(for: sourceDir)
        }
        if let recording = createRecording(from: url, sourceDirectory: sourceDir, storageLocation: storageLocation) {
            DispatchQueue.main.async { self.recordings.insert(recording, at: 0) }
        }
    }

    func deleteRecording(_ recording: Recording) {
        do { try FileManager.default.removeItem(at: recording.filePath); DispatchQueue.main.async { self.recordings.removeAll { $0.id == recording.id } } } catch { print("Error deleting recording: \(error)") }
    }

    func openInFinder(_ recording: Recording) { NSWorkspace.shared.selectFile(recording.filePath.path, inFileViewerRootedAtPath: "") }
    func openRecording(_ recording: Recording) { NSWorkspace.shared.open(recording.filePath) }

    func generateThumbnail(for recording: Recording) async -> NSImage? {
        guard recording.isAvailable else { return nil }
        let asset = AVURLAsset(url: recording.filePath)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 180)
        do { let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil); return NSImage(cgImage: cgImage, size: NSSize(width: 320, height: 180)) } catch { return nil }
    }
}
