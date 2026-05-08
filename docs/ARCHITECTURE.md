# Architecture

IP Camera Viewer is a Swift Package Manager macOS app built around SwiftUI, Observation, AVKit, WebKit, URLSession, Keychain Services, and local ffmpeg processes.

## High-Level Flow

```text
SwiftUI views
  -> CameraStore and DiscoveryStore
  -> discovery, stream, PTZ, and bridge services
  -> local network cameras, Keychain, Application Support, ffmpeg
```

## App Lifecycle

`IPCameraViewerApp` owns the main window, app commands, settings scene, and lifecycle delegate.

On launch and termination, `BridgeProcessCleanup` removes leftover RTSP and composite bridge processes and temporary HLS directories. The app also terminates after the last window closes, which helps prevent orphaned ffmpeg/http server work.

## Persistence

`CameraStore` persists:

- Cameras to `~/Library/Application Support/IPCameraViewer/cameras.json`.
- Saved views to `~/Library/Application Support/IPCameraViewer/camera-views.json`.

Both JSON files are written atomically and marked with owner-only permissions.

Camera passwords are stored separately with `CameraCredentialStore` in the macOS Keychain under the service `IPCameraViewer.CameraCredentials`. Legacy passwords found in camera JSON are migrated into Keychain when possible and then removed from JSON.

## Discovery

Discovery combines several strategies:

- ONVIF WS-Discovery.
- Bonjour/mDNS service discovery.
- SSDP/UPnP discovery.
- Known-host probing.
- Bounded local port probing for common camera ports.

Discovery results are best-effort. Many cameras advertise device endpoints rather than final stream paths, so users may need to edit the camera URL, username, password, or RTSP path after adding a discovered camera.

## Playback

Playback is selected from the camera URL:

- Web and HTTP camera pages use a WebKit-backed view.
- HLS streams use AVPlayer.
- MJPEG streams use the web path where supported by the camera.
- RTSP streams are bridged to local HLS with ffmpeg, then played with AVPlayer.

Quality presets control bridge height, frame rate, bitrate, encoder preset, Dahua/Intelbras stream subtype, and composite tile size.

Encoding modes:

- Low CPU uses `h264_videotoolbox`.
- Compatibility uses `libx264`.

## Multi-Camera Views

`CameraViewLayout` stores saved views with:

- Camera IDs.
- Column count.
- Minimum tile width.
- Fit-to-available-width mode.
- Cast quality preset.
- Cast encoder mode.

The dashboard renders a responsive grid from the current saved view and live camera list.

## Cast View

`CompositeViewBridgeService` opens the selected camera streams with ffmpeg, composes them into a single tiled video, writes local HLS output, and serves that output for AVPlayer/AirPlay.

If an input camera cannot be opened, the service skips or reports it depending on whether any playable inputs remain.

## PTZ

`PTZControlService` sends PTZ commands to supported cameras. The service handles authenticated requests and camera-specific command formats where implemented.

PTZ behavior varies heavily by camera model and firmware. A camera can support PTZ in its vendor app while requiring a different local API, route, or permission level for third-party control.

## Logging

The app uses `OSLog` through the loggers in `Support/AppLoggers.swift`.

Logs should never include raw passwords or credential-bearing URLs. When a URL must appear in an error message, credentials should be redacted first.
