import SwiftUI
import AppKit

struct EditRecordingView: View {
    let recording: Recording
    @Environment(\.dismiss) private var dismiss

    @State private var sectionsText: String = """
        # One section per line. Examples:
        #
        # 00:01:30  How I built my trading bot
        # the bug I ran into
        # what I learned this week
        #
        # Lines with a leading HH:MM:SS use that exact timestamp.
        # Lines with no timestamp are auto-located by transcribing
        # your video and matching the words you said.
        """
    @State private var cardDuration: Double = 3.0
    @State private var isRunning = false
    @State private var logLines: [String] = []
    @State private var resultURL: URL?
    @State private var errorMessage: String?

    private let vidcutPath = "/Users/solomon/Projects/vidcut/vidcut"

    var outputURL: URL {
        recording.filePath
            .deletingPathExtension()
            .appendingPathExtension("edited.mp4")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            HSplitView {
                sectionsEditor
                    .frame(minWidth: 320)
                logPane
                    .frame(minWidth: 320)
            }

            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Edit Recording").font(.headline)
                Text(recording.filename)
                    .font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    private var sectionsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Section titles")
                .font(.subheadline).fontWeight(.medium)
            TextEditor(text: $sectionsText)
                .font(.system(.body, design: .monospaced))
                .padding(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .disabled(isRunning)

            HStack {
                Text("Card duration")
                Slider(value: $cardDuration, in: 1.5...6.0, step: 0.5)
                    .frame(maxWidth: 160)
                    .disabled(isRunning)
                Text(String(format: "%.1fs", cardDuration))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            .font(.caption)
        }
        .padding()
    }

    private var logPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Progress")
                .font(.subheadline).fontWeight(.medium)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logLines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                        Color.clear.frame(height: 1).id("__bottom__")
                    }.padding(8)
                }
                .background(Color.black.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .onChange(of: logLines.count) { _ in
                    withAnimation(.linear(duration: 0.1)) {
                        proxy.scrollTo("__bottom__", anchor: .bottom)
                    }
                }
            }
            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            if isRunning {
                ProgressView().controlSize(.small)
                Text("Running vidcut splice…")
                    .font(.caption).foregroundColor(.secondary)
            } else if let url = resultURL {
                Text("Done")
                    .font(.caption).foregroundColor(.green)
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            Spacer()
            Button("Generate") { run() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isRunning || !FileManager.default.fileExists(atPath: vidcutPath))
                .help(FileManager.default.fileExists(atPath: vidcutPath)
                      ? "Run vidcut splice on this recording"
                      : "vidcut CLI not found at \(vidcutPath)")
        }
        .padding()
    }

    private func run() {
        errorMessage = nil
        resultURL = nil
        logLines.removeAll()

        let outURL = outputURL
        let sectionsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vidcut-sections-\(UUID().uuidString).txt")

        do {
            try sectionsText.write(to: sectionsURL, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "couldn't write sections file: \(error.localizedDescription)"
            return
        }

        isRunning = true
        appendLog("$ vidcut splice \(recording.filePath.path) <sections> -o \(outURL.path)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: vidcutPath)
        process.arguments = [
            "splice",
            recording.filePath.path,
            sectionsURL.path,
            "-o", outURL.path,
            "--card-duration", String(format: "%.1f", cardDuration),
        ]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        stdoutHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self.appendLog(s) }
        }
        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self.appendLog(s) }
        }

        process.terminationHandler = { proc in
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            try? FileManager.default.removeItem(at: sectionsURL)

            DispatchQueue.main.async {
                self.isRunning = false
                if proc.terminationStatus == 0 {
                    self.resultURL = outURL
                    self.appendLog("✓ exit 0 — wrote \(outURL.lastPathComponent)")
                    NSWorkspace.shared.open(outURL)
                } else {
                    self.errorMessage = "vidcut exited with code \(proc.terminationStatus)"
                    self.appendLog("✗ exit \(proc.terminationStatus)")
                }
            }
        }

        do {
            try process.run()
        } catch {
            isRunning = false
            errorMessage = "couldn't launch vidcut: \(error.localizedDescription)"
        }
    }

    private func appendLog(_ chunk: String) {
        for line in chunk.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if !s.isEmpty || logLines.last?.isEmpty == false {
                logLines.append(s)
            }
        }
    }
}
