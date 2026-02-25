import Foundation

struct Recording: Identifiable, Codable, Hashable {
    let id: UUID
    let filename: String
    let createdAt: Date
    let duration: TimeInterval
    let fileSize: Int64
    let thumbnailPath: String?
    var sourceDirectory: URL?
    var storageLocation: String

    init(id: UUID, filename: String, createdAt: Date, duration: TimeInterval, fileSize: Int64, thumbnailPath: String?, sourceDirectory: URL? = nil, storageLocation: String = "Internal") {
        self.id = id
        self.filename = filename
        self.createdAt = createdAt
        self.duration = duration
        self.fileSize = fileSize
        self.thumbnailPath = thumbnailPath
        self.sourceDirectory = sourceDirectory
        self.storageLocation = storageLocation
    }

    var filePath: URL {
        if let dir = sourceDirectory {
            return dir.appendingPathComponent(filename)
        }
        return RecordingsManager.recordingsDirectory.appendingPathComponent(filename)
    }

    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: filePath.path)
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}
