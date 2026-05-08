import CryptoKit
import Darwin
import Foundation
import Observation

enum CompositeViewBridgeState: Equatable {
    case idle
    case starting
    case streaming(URL)
    case missingFFmpeg
    case failed(String)
}

@Observable
@MainActor
final class CompositeViewBridgeSession {
    private(set) var state: CompositeViewBridgeState = .idle
    private(set) var skippedCameraNames: [String] = []

    private var process: Process?
    private var httpServerProcess: Process?
    private var outputDirectory: URL?
    private var currentSignature = ""
    private var redactedInputs: [String: String] = [:]
    private var lastBridgeError = ""

    func start(cameraView: CameraViewLayout, cameras: [Camera]) {
        let candidateInputs = playableInputs(from: cameras)
        let signature = cameraViewSignature(cameraView: cameraView, inputs: candidateInputs)
        guard currentSignature != signature || process == nil else { return }

        stop()
        currentSignature = signature
        lastBridgeError = ""
        skippedCameraNames = []
        state = .starting

        guard !candidateInputs.isEmpty else {
            state = .failed("This view has no cameras with playable stream URLs. Edit the cameras and add saved passwords before casting.")
            return
        }

        Task {
            let validatedInputs = await Self.validatedInputs(candidateInputs)
            await MainActor.run {
                let validIDs = Set(validatedInputs.map(\.camera.id))
                self.skippedCameraNames = cameras
                    .filter { !validIDs.contains($0.id) }
                    .map(\.name)
                self.startValidatedInputs(validatedInputs, cameraView: cameraView)
            }
        }
    }

    private func startValidatedInputs(_ inputs: [CompositeInput], cameraView: CameraViewLayout) {
        redactedInputs = Dictionary(uniqueKeysWithValues: inputs.map { ($0.url.absoluteString, redacted($0.url)) })

        guard !inputs.isEmpty else {
            state = .failed("None of the selected cameras opened for casting. Check usernames, passwords, and stream paths.")
            return
        }

        guard let ffmpegURL = Self.ffmpegExecutableURL() else {
            AppLoggers.streams.error("Cannot start composite view bridge because ffmpeg was not found")
            state = .missingFFmpeg
            return
        }

        let directory = Self.outputDirectory(for: cameraViewSignature(cameraView: cameraView, inputs: inputs))
        let playlistURL = directory.appending(path: "stream.m3u8")
        outputDirectory = directory

        do {
            try FileManager.default.removeCompositeItemIfExists(at: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let httpURL = try startHTTPServer(serving: directory)

            let process = Process()
            process.executableURL = ffmpegURL
            process.arguments = ffmpegArguments(
                inputs: inputs,
                cameraView: cameraView,
                directory: directory,
                playlistURL: playlistURL
            )

            let errorPipe = Pipe()
            process.standardError = errorPipe
            errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty,
                      let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !message.isEmpty else {
                    return
                }
                Task { @MainActor in
                    self?.recordBridgeError(message)
                }
            }

            process.terminationHandler = { [weak self, weak errorPipe] process in
                errorPipe?.fileHandleForReading.readabilityHandler = nil
                Task { @MainActor in
                    self?.processDidTerminate(process)
                }
            }

            try process.run()
            self.process = process
            AppLoggers.streams.info("Started composite view bridge with \(inputs.count, privacy: .public) input(s)")
            waitForPlaylist(at: playlistURL, playbackURL: httpURL.appending(path: "stream.m3u8"))
        } catch {
            AppLoggers.streams.error("Failed to start composite view bridge: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        process?.terminationHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        if httpServerProcess?.isRunning == true {
            httpServerProcess?.terminate()
        }
        process = nil
        httpServerProcess = nil
        outputDirectory = nil
        currentSignature = ""
        redactedInputs = [:]
        skippedCameraNames = []
    }

    private func playableInputs(from cameras: [Camera]) -> [CompositeInput] {
        cameras.compactMap { camera in
            guard !camera.requiresUnavailablePassword,
                  let url = camera.playbackURL else {
                return nil
            }

            switch camera.streamKind {
            case .rtsp, .hls, .web:
                return CompositeInput(camera: camera, url: url)
            case .unknown:
                return nil
            }
        }
    }

    private func ffmpegArguments(
        inputs: [CompositeInput],
        cameraView: CameraViewLayout,
        directory: URL,
        playlistURL: URL
    ) -> [String] {
        let columns = min(max(cameraView.columnCount, 1), 6)
        let rows = Int(ceil(Double(inputs.count) / Double(columns)))
        let totalSlots = rows * columns
        let blankSlots = totalSlots - inputs.count
        let quality = cameraView.qualityPreset
        let tileSize = quality.compositeTileSize

        var arguments = [
            "-hide_banner",
            "-loglevel", "warning"
        ]

        for input in inputs {
            if input.url.scheme?.lowercased().hasPrefix("rtsp") == true {
                arguments.append(contentsOf: ["-rtsp_transport", "tcp"])
            }
            arguments.append(contentsOf: [
                "-thread_queue_size", "512",
                "-i", input.url.absoluteString
            ])
        }

        for _ in 0..<blankSlots {
            arguments.append(contentsOf: [
                "-f", "lavfi",
                "-i", "color=c=black:s=\(tileSize):r=\(quality.bridgeFPS)"
            ])
        }

        arguments.append(contentsOf: [
            "-filter_complex", filterComplex(
                inputCount: inputs.count,
                totalSlots: totalSlots,
                columns: columns,
                rows: rows,
                quality: quality
            ),
            "-map", "[grid]",
            "-an",
        ])
        arguments.append(contentsOf: encoderArguments(quality: quality, encodingMode: cameraView.encodingMode))
        arguments.append(contentsOf: [
            "-b:v", quality.videoBitrate,
            "-maxrate", quality.videoBitrate,
            "-bufsize", quality.videoBitrate,
            "-pix_fmt", "yuv420p",
            "-r", "\(quality.bridgeFPS)",
            "-g", "\(quality.bridgeFPS * 2)",
            "-keyint_min", "\(quality.bridgeFPS * 2)",
            "-sc_threshold", "0",
            "-f", "hls",
            "-hls_time", "1",
            "-hls_list_size", "6",
            "-hls_flags", "delete_segments+omit_endlist+independent_segments",
            "-hls_segment_filename", directory.appending(path: "segment-%03d.ts").path,
            playlistURL.path
        ])

        return arguments
    }

    private func filterComplex(
        inputCount: Int,
        totalSlots: Int,
        columns: Int,
        rows: Int,
        quality: StreamQualityPreset
    ) -> String {
        var filters: [String] = []
        let dimensions = quality.compositeTileDimensions
        let width = dimensions.width
        let height = dimensions.height
        let fps = quality.bridgeFPS

        for slot in 0..<totalSlots {
            if slot < inputCount {
                filters.append("[\(slot):v]setpts=PTS-STARTPTS,fps=\(fps),scale=\(width):\(height):force_original_aspect_ratio=decrease,pad=\(width):\(height):(ow-iw)/2:(oh-ih)/2,setsar=1[v\(slot)]")
            } else {
                filters.append("[\(slot):v]setsar=1[v\(slot)]")
            }
        }

        for row in 0..<rows {
            let rowInputs = (0..<columns)
                .map { "[v\(row * columns + $0)]" }
                .joined()
            filters.append("\(rowInputs)hstack=inputs=\(columns)[row\(row)]")
        }

        if rows == 1 {
            filters.append("[row0]copy[grid]")
        } else {
            let rowInputs = (0..<rows)
                .map { "[row\($0)]" }
                .joined()
            filters.append("\(rowInputs)vstack=inputs=\(rows)[grid]")
        }

        return filters.joined(separator: ";")
    }

    private func waitForPlaylist(at playlistURL: URL, playbackURL: URL) {
        Task { [weak self] in
            for _ in 0..<240 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self else { return }
                guard self.process?.isRunning == true else {
                    if FileManager.default.fileExists(atPath: playlistURL.path) {
                        self.state = .streaming(playbackURL)
                    } else {
                        self.state = .failed(self.failureMessage(prefix: "The composite view bridge stopped before video was ready."))
                    }
                    return
                }

                if FileManager.default.fileExists(atPath: playlistURL.path) {
                    self.state = .streaming(playbackURL)
                    AppLoggers.streams.info("Composite view bridge playlist is ready")
                    return
                }
            }

            self?.state = .failed(self?.failureMessage(prefix: "The composite view bridge started, but no HLS playlist was produced.") ?? "The composite view bridge did not produce video.")
        }
    }

    private func startHTTPServer(serving directory: URL) throws -> URL {
        let port = try Self.availableLocalPort()
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/python3")
        process.arguments = [
            "-m", "http.server",
            "\(port)",
            "--bind", "127.0.0.1",
            "--directory", directory.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        httpServerProcess = process
        AppLoggers.streams.info("Started composite HLS server on port \(port, privacy: .public)")
        return URL(string: "http://127.0.0.1:\(port)")!
    }

    private func processDidTerminate(_ terminatedProcess: Process) {
        guard process === terminatedProcess else { return }
        process = nil
        switch state {
        case .streaming:
            state = .failed("The composite view bridge stopped.")
        case .starting:
            state = .failed(failureMessage(prefix: "The composite view bridge could not start the stream."))
        default:
            break
        }
    }

    private func recordBridgeError(_ message: String) {
        let sanitizedMessage = sanitized(message)
        if isNonFatalFFmpegMessage(sanitizedMessage) {
            AppLoggers.streams.debug("ffmpeg composite bridge: \(sanitizedMessage, privacy: .public)")
        } else {
            lastBridgeError = sanitizedMessage
            AppLoggers.streams.error("ffmpeg composite bridge: \(sanitizedMessage, privacy: .public)")
            if isTerminalFFmpegMessage(sanitizedMessage) {
                process?.terminate()
                state = .failed(failureMessage(prefix: "The composite view bridge could not start the stream."))
            }
        }
    }

    private func isNonFatalFFmpegMessage(_ message: String) -> Bool {
        let lowercasedMessage = message.lowercased()
        return lowercasedMessage.contains("timestamps are unset") ||
            lowercasedMessage.contains("deprecated") ||
            lowercasedMessage.contains("will stop working in the future")
    }

    private func isTerminalFFmpegMessage(_ message: String) -> Bool {
        let lowercasedMessage = message.lowercased()
        return lowercasedMessage.contains("401") ||
            lowercasedMessage.contains("unauthorized") ||
            lowercasedMessage.contains("404") ||
            lowercasedMessage.contains("not found") ||
            lowercasedMessage.contains("unknown encoder") ||
            lowercasedMessage.contains("error while opening encoder") ||
            lowercasedMessage.contains("error opening input")
    }

    private func encoderArguments(quality: StreamQualityPreset, encodingMode: StreamEncodingMode) -> [String] {
        switch encodingMode {
        case .lowCPU:
            [
                "-c:v", encodingMode.ffmpegCodec,
                "-realtime", "1",
                "-allow_sw", "1"
            ]
        case .compatibility:
            [
                "-c:v", encodingMode.ffmpegCodec,
                "-preset", quality.encoderPreset,
                "-tune", "zerolatency"
            ]
        }
    }

    private func failureMessage(prefix: String) -> String {
        guard !lastBridgeError.isEmpty else {
            return "\(prefix) Check the camera URLs, usernames, passwords, and stream paths."
        }

        let lowercasedError = lastBridgeError.lowercased()
        if lowercasedError.contains("401") || lowercasedError.contains("unauthorized") {
            return "\(prefix) One of the cameras rejected authentication. Edit that camera and set the correct username and password."
        }

        if lowercasedError.contains("404") || lowercasedError.contains("not found") {
            return "\(prefix) One of the camera stream paths was not found."
        }

        if lowercasedError.contains("timed out") || lowercasedError.contains("no route") || lowercasedError.contains("host is down") {
            return "\(prefix) One of the cameras did not answer on the network."
        }

        return "\(prefix) \(lastBridgeError)"
    }

    private func sanitized(_ message: String) -> String {
        redactedInputs.reduce(message) { output, entry in
            output.replacingOccurrences(of: entry.key, with: entry.value)
        }
    }

    private func redacted(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let hasPassword = components?.password != nil
        if components?.user != nil {
            components?.user = "user"
            components?.password = hasPassword ? "password" : nil
        }
        return components?.url?.absoluteString ?? url.absoluteString
    }

    private func cameraViewSignature(cameraView: CameraViewLayout, inputs: [CompositeInput]) -> String {
        [
            cameraView.id.uuidString,
            "\(cameraView.columnCount)",
            "\(cameraView.tileWidth)",
            cameraView.qualityPreset.rawValue,
            cameraView.encodingMode.rawValue,
            inputs.map { $0.url.absoluteString }.joined(separator: "|")
        ].joined(separator: "::")
    }

    private nonisolated static func ffmpegExecutableURL() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/opt/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(filePath: path)
        }

        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        for directory in pathEntries {
            let path = URL(filePath: directory).appending(path: "ffmpeg").path
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(filePath: path)
            }
        }

        return nil
    }

    private nonisolated static func ffprobeExecutableURL() -> URL? {
        guard let ffmpegURL = ffmpegExecutableURL() else { return nil }
        let ffprobeURL = ffmpegURL.deletingLastPathComponent().appending(path: "ffprobe")
        guard FileManager.default.isExecutableFile(atPath: ffprobeURL.path) else { return nil }
        return ffprobeURL
    }

    private nonisolated static func validatedInputs(_ inputs: [CompositeInput]) async -> [CompositeInput] {
        await Task.detached(priority: .userInitiated) {
            inputs.filter { input in
                inputCanOpen(input)
            }
        }.value
    }

    private nonisolated static func inputCanOpen(_ input: CompositeInput) -> Bool {
        guard let ffprobeURL = ffprobeExecutableURL() else { return true }
        guard input.url.user(percentEncoded: false) == nil,
              input.url.password(percentEncoded: false) == nil else {
            return true
        }

        let process = Process()
        process.executableURL = ffprobeURL
        var arguments = [
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=codec_type",
            "-of", "default=noprint_wrappers=1:nokey=1"
        ]
        if input.url.scheme?.lowercased().hasPrefix("rtsp") == true {
            arguments.insert(contentsOf: ["-rtsp_transport", "tcp"], at: 2)
        }
        arguments.append(input.url.absoluteString)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return false
        }

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 5) == .timedOut {
            process.terminate()
            return false
        }

        return process.terminationStatus == 0
    }

    private static func outputDirectory(for signature: String) -> URL {
        let digest = SHA256.hash(data: Data(signature.utf8))
        let id = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.temporaryDirectory
            .appending(path: "IPCameraViewer", directoryHint: .isDirectory)
            .appending(path: "CompositeBridge-\(id)-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private static func availableLocalPort() throws -> Int {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard socketDescriptor >= 0 else {
            throw POSIXError(.EIO)
        }
        defer { close(socketDescriptor) }

        var reuse: Int32 = 1
        setsockopt(socketDescriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(socketDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var socketAddress = sockaddr_in()
        var socketAddressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &socketAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { reboundPointer in
                getsockname(socketDescriptor, reboundPointer, &socketAddressLength)
            }
        }
        guard nameResult == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        return Int(UInt16(bigEndian: socketAddress.sin_port))
    }
}

private struct CompositeInput {
    let camera: Camera
    let url: URL
}

private extension FileManager {
    func removeCompositeItemIfExists(at url: URL) throws {
        guard fileExists(atPath: url.path) else { return }
        try removeItem(at: url)
    }
}
