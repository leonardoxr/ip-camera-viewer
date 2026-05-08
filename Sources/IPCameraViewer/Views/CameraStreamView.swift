import AVKit
import AppKit
import OSLog
import SwiftUI
import WebKit

enum CameraStreamMode {
    case preview
    case full
}

struct CameraStreamView: View {
    let camera: Camera
    let mode: CameraStreamMode
    @AppStorage(AppPreferenceKey.showPreviewNameBadges) private var showPreviewNameBadges = true

    var body: some View {
        Group {
            if mode == .full && camera.requiresUnavailablePassword {
                StreamMessageView(
                    title: "Password Required",
                    message: "This camera has a username, but no password is available. Choose Always Allow in the Keychain prompt, or edit the camera and enter the password again.",
                    systemImage: "lock"
                )
            } else if let url = streamURL {
                switch camera.streamKind {
                case .web:
                    WebCameraView(url: url)
                case .hls:
                    HLSCameraView(url: url)
                case .rtsp:
                    if mode == .preview {
                        StreamMessageView(
                            title: "RTSP Camera",
                            message: "Open the camera to start the RTSP bridge.",
                            systemImage: "antenna.radiowaves.left.and.right"
                        )
                    } else {
                        RTSPBridgeCameraView(url: url, quality: camera.qualityPreset, encodingMode: camera.encodingMode)
                    }
                case .unknown:
                    StreamMessageView(
                        title: "Unsupported Stream",
                        message: "Use an HTTP, HTTPS, MJPEG, or HLS .m3u8 camera URL.",
                        systemImage: "questionmark.video"
                    )
                }
            } else {
                StreamMessageView(
                    title: "Invalid URL",
                    message: "Check the camera address and include a scheme such as http:// or https://.",
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
        .background(Color.black)
        .overlay(alignment: .topLeading) {
            if mode == .preview && showPreviewNameBadges {
                Text(camera.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(8)
            }
        }
    }

    private var streamURL: URL? {
        mode == .preview ? camera.normalizedStreamURL : camera.playbackURL
    }
}

struct WebCameraView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            AppLoggers.streams.info("Loaded web camera stream")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            AppLoggers.streams.error("Web camera stream failed: \(error.localizedDescription, privacy: .public)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            AppLoggers.streams.error("Web camera provisional load failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

struct HLSCameraView: View {
    let url: URL
    @State private var player: AVPlayer

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        AVPlayerCameraView(player: player)
            .onAppear {
                AppLoggers.streams.info("Started HLS playback")
                player.play()
            }
            .onChange(of: url) { _, newURL in
                player.replaceCurrentItem(with: AVPlayerItem(url: newURL))
                player.play()
            }
            .onDisappear {
                AppLoggers.streams.info("Paused HLS playback")
                player.pause()
            }
    }
}

private struct AVPlayerCameraView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .floating
        playerView.videoGravity = .resizeAspect
        playerView.player = player
        return playerView
    }

    func updateNSView(_ playerView: AVPlayerView, context: Context) {
        if playerView.player !== player {
            playerView.player = player
        }
    }
}

private struct RTSPBridgeCameraView: View {
    let url: URL
    let quality: StreamQualityPreset
    let encodingMode: StreamEncodingMode
    @State private var bridge = RTSPBridgeSession()

    var body: some View {
        Group {
            switch bridge.state {
            case .idle, .starting:
                StreamMessageView(
                    title: "Starting RTSP Bridge",
                    message: "Converting this RTSP stream to a local HLS feed.",
                    systemImage: "antenna.radiowaves.left.and.right",
                    showsProgress: true
                )
            case .streaming(let playlistURL):
                HLSCameraView(url: playlistURL)
            case .missingFFmpeg:
                StreamMessageView(
                    title: "Install ffmpeg",
                    message: "RTSP playback needs ffmpeg installed at /opt/homebrew/bin/ffmpeg or another standard PATH location.",
                    systemImage: "terminal"
                )
            case .failed(let message):
                StreamMessageView(
                    title: "RTSP Bridge Failed",
                    message: message,
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
        .task(id: "\(url.absoluteString)-\(quality.rawValue)-\(encodingMode.rawValue)") {
            bridge.start(inputURL: url, quality: quality, encodingMode: encodingMode)
        }
        .onDisappear {
            bridge.stop()
        }
    }
}

struct StreamMessageView: View {
    let title: String
    let message: String
    let systemImage: String
    var showsProgress = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 6)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
