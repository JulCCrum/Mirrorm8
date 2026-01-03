import Foundation

struct Recording: Identifiable, Codable, Hashable {
    let id: UUID
    let filename: String
    let createdAt: Date
    let duration: TimeInterval
    let fileSize: Int64
    let thumbnailPath: String?

    var filePath: URL {
        RecordingsManager.recordingsDirectory.appendingPathComponent(filename)
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
