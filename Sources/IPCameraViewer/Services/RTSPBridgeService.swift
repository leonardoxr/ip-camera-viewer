import CryptoKit
import Darwin
import Foundation
import Observation

enum RTSPBridgeState: Equatable {
    case idle
    case starting
    case streaming(URL)
    case missingFFmpeg
    case failed(String)
}

@Observable
@MainActor
final class RTSPBridgeSession {
    private(set) var state: RTSPBridgeState = .idle

    private var process: Process?
    private var httpServerProcess: Process?
    private var outputDirectory: URL?
    private var currentInputURL: URL?
    private var currentQuality = StreamQualityPreset.balanced
    private var currentEncodingMode = StreamEncodingMode.lowCPU
    private var lastBridgeError = ""

    func start(
        inputURL: URL,
        quality: StreamQualityPreset = .balanced,
        encodingMode: StreamEncodingMode = .lowCPU
    ) {
        guard currentInputURL != inputURL ||
            currentQuality != quality ||
            currentEncodingMode != encodingMode ||
            process == nil else {
            return
        }
        stop()
        currentInputURL = inputURL
        currentQuality = quality
        currentEncodingMode = encodingMode
        lastBridgeError = ""
        state = .starting

        guard let ffmpegURL = Self.ffmpegExecutableURL() else {
            AppLoggers.streams.error("Cannot start RTSP bridge because ffmpeg was not found")
            state = .missingFFmpeg
            return
        }

        let directory = Self.outputDirectory(for: inputURL)
        let playlistURL = directory.appending(path: "stream.m3u8")
        outputDirectory = directory

        do {
            try FileManager.default.removeItemIfExists(at: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let httpURL = try startHTTPServer(serving: directory)

            let process = Process()
            process.executableURL = ffmpegURL
            var arguments = [
                "-hide_banner",
                "-loglevel", "warning",
                "-fflags", "+genpts",
                "-rtsp_transport", "tcp",
                "-i", inputURL.absoluteString,
                "-an",
                "-vf", "scale=-2:\(quality.bridgeHeight):force_original_aspect_ratio=decrease"
            ]
            arguments.append(contentsOf: encoderArguments(quality: quality, encodingMode: encodingMode))
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
            process.arguments = arguments

            let errorPipe = Pipe()
            process.standardError = errorPipe
            let session = self
            errorPipe.fileHandleForReading.readabilityHandler = { [weak session] handle in
                let data = handle.availableData
                guard !data.isEmpty,
                      let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !message.isEmpty else {
                    return
                }
                Task { @MainActor [weak session] in
                    session?.recordBridgeError(message)
                }
            }

            process.terminationHandler = { [weak session, weak errorPipe] process in
                errorPipe?.fileHandleForReading.readabilityHandler = nil
                Task { @MainActor [weak session] in
                    session?.processDidTerminate(process)
                }
            }

            try process.run()
            self.process = process
            AppLoggers.streams.info("Started RTSP bridge for \(inputURL.host(percentEncoded: false) ?? "unknown host", privacy: .public)")
            waitForPlaylist(at: playlistURL, playbackURL: httpURL.appending(path: "stream.m3u8"))
        } catch {
            AppLoggers.streams.error("Failed to start RTSP bridge: \(error.localizedDescription, privacy: .public)")
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
        currentInputURL = nil
        outputDirectory = nil
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
                        self.state = .failed(self.failureMessage(prefix: "The RTSP bridge stopped before video was ready."))
                    }
                    return
                }

                if FileManager.default.fileExists(atPath: playlistURL.path) {
                    self.state = .streaming(playbackURL)
                    AppLoggers.streams.info("RTSP bridge playlist is ready")
                    return
                }
            }

            self?.state = .failed(self?.failureMessage(prefix: "The RTSP bridge started, but no HLS playlist was produced.") ?? "The RTSP bridge did not produce video.")
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
        AppLoggers.streams.info("Started local HLS server on port \(port, privacy: .public)")
        return URL(string: "http://127.0.0.1:\(port)")!
    }

    private func processDidTerminate(_ terminatedProcess: Process) {
        guard process === terminatedProcess else { return }
        process = nil
        switch state {
        case .streaming:
            state = .failed("The RTSP bridge stopped.")
        case .starting:
            state = .failed(failureMessage(prefix: "The RTSP bridge could not start the stream."))
        default:
            break
        }
    }

    private func recordBridgeError(_ message: String) {
        let sanitizedMessage = sanitized(message)
        if isNonFatalFFmpegMessage(sanitizedMessage) {
            AppLoggers.streams.debug("ffmpeg RTSP bridge: \(sanitizedMessage, privacy: .public)")
        } else {
            lastBridgeError = sanitizedMessage
            AppLoggers.streams.error("ffmpeg RTSP bridge: \(sanitizedMessage, privacy: .public)")
            if isTerminalFFmpegMessage(sanitizedMessage) {
                process?.terminate()
                state = .failed(failureMessage(prefix: "The RTSP bridge could not start the stream."))
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
            return "\(prefix) Check the RTSP URL, username, password, and camera stream path."
        }

        let lowercasedError = lastBridgeError.lowercased()
        if lowercasedError.contains("401") || lowercasedError.contains("unauthorized") {
            return "\(prefix) The camera rejected authentication. Edit the camera and set the correct username and password."
        }

        if lowercasedError.contains("404") || lowercasedError.contains("not found") {
            return "\(prefix) The camera answered, but the RTSP path was not found. Check the stream path after the host and port."
        }

        if lowercasedError.contains("timed out") || lowercasedError.contains("no route") || lowercasedError.contains("host is down") {
            return "\(prefix) The camera did not answer on the network. Check the IP address and router isolation."
        }

        return "\(prefix) \(lastBridgeError)"
    }

    private func sanitized(_ message: String) -> String {
        guard let currentInputURL else { return message }

        var redactedComponents = URLComponents(url: currentInputURL, resolvingAgainstBaseURL: false)
        let hasPassword = redactedComponents?.password != nil
        if redactedComponents?.user != nil {
            redactedComponents?.user = "user"
            redactedComponents?.password = hasPassword ? "password" : nil
        }

        guard let redactedURL = redactedComponents?.url?.absoluteString else { return message }
        return message.replacingOccurrences(of: currentInputURL.absoluteString, with: redactedURL)
    }

    nonisolated static func ffmpegExecutableURL() -> URL? {
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

    private static func outputDirectory(for inputURL: URL) -> URL {
        let digest = SHA256.hash(data: Data(inputURL.absoluteString.utf8))
        let id = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.temporaryDirectory
            .appending(path: "IPCameraViewer", directoryHint: .isDirectory)
            .appending(path: "RTSPBridge-\(id)-\(UUID().uuidString)", directoryHint: .isDirectory)
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

private extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        guard fileExists(atPath: url.path) else { return }
        try removeItem(at: url)
    }
}
