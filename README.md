# IP Camera Viewer

IP Camera Viewer is a native macOS app for discovering, saving, viewing, organizing, and casting local IP camera feeds.

It is built with SwiftUI and Swift Package Manager. The app is designed for local-network cameras and NVRs, with support for common discovery protocols, authenticated RTSP/HLS/MJPEG streams, PTZ controls where the camera exposes a compatible API, and multi-camera views.

## Features

- Discover cameras with ONVIF WS-Discovery, Bonjour/mDNS, SSDP/UPnP, and bounded local port probing.
- Add cameras manually or from discovery results without leaving the discovery list.
- Save camera metadata and organize cameras by location.
- Store camera passwords in the macOS Keychain instead of the app metadata JSON.
- Play HTTP camera pages, MJPEG streams, HLS streams, and RTSP streams bridged through ffmpeg.
- Choose playback quality presets: High, Balanced, Fast, and Stable.
- Choose encoding mode: Low CPU hardware encoding with VideoToolbox, or Compatibility mode with libx264.
- Create saved multi-camera views with configurable columns, tile widths, and fit-to-window layout.
- Cast a saved view as one AirPlay-capable HLS stream.
- Send PTZ commands for supported cameras.
- Clean up local ffmpeg and temporary HLS bridge processes when the app exits.

## Requirements

- macOS 14 or newer.
- Swift 6.2 or newer.
- Xcode Command Line Tools.
- `ffmpeg` for RTSP playback, transcoding, and view casting.

Install command line tools:

```bash
xcode-select --install
```

Install ffmpeg with Homebrew:

```bash
brew install ffmpeg
```

The app looks for ffmpeg in common locations such as `/opt/homebrew/bin/ffmpeg`, `/usr/local/bin/ffmpeg`, `/opt/local/bin/ffmpeg`, and PATH directories.

## Run Locally

Build and launch the app bundle:

```bash
./script/build_and_run.sh
```

Build without launching:

```bash
swift build
```

Run with app logs:

```bash
./script/build_and_run.sh --logs
```

Run with telemetry logs:

```bash
./script/build_and_run.sh --telemetry
```

Build the `.app` bundle without launching it:

```bash
./script/build_and_run.sh --package
```

## Camera URLs

The app accepts several stream styles:

- `http://camera.local/`
- `http://192.168.1.20/video.cgi`
- `http://192.168.1.20/mjpeg`
- `http://192.168.1.20/live.m3u8`
- `rtsp://192.168.1.20:554/cam/realmonitor?channel=1&subtype=0`

For Intelbras and Dahua-style cameras, the app can infer a default RTSP path from host, username, password, and quality preset. Discovery may only find the device endpoint, so you may still need to edit the stream path after adding a camera.

## Discovery Notes

Being on 5 GHz while a camera is on 2.4 GHz should be fine if both radios are bridged into the same LAN. Discovery can fail when the router uses guest networks, client isolation, VLANs, IoT isolation, or multicast filtering between bands.

If discovery misses a camera, try the direct IP probe in the Discover sheet with a known address such as `192.168.1.20`.

## Privacy And Security

IP Camera Viewer is local-first. It does not use a cloud service or send camera data to a third-party API.

Stored files:

- Camera metadata: `~/Library/Application Support/IPCameraViewer/cameras.json`
- Saved view metadata: `~/Library/Application Support/IPCameraViewer/camera-views.json`
- Camera passwords: macOS Keychain service `IPCameraViewer.CameraCredentials`
- Temporary HLS bridge output: the user temporary directory under `IPCameraViewer/`

Known caveat: when an RTSP URL with embedded credentials is bridged by ffmpeg, the input URL is passed to the local ffmpeg process. Avoid sharing process listings, crash logs, or terminal captures when they may contain credentials. See [docs/PRIVACY.md](docs/PRIVACY.md) and [SECURITY.md](SECURITY.md).

## Project Layout

```text
Sources/IPCameraViewer/
  App/        App entry point and macOS lifecycle cleanup.
  Models/     Camera, view layout, quality, and encoding models.
  Services/   Discovery, RTSP bridge, composite bridge, PTZ, and Keychain services.
  Stores/     Camera and saved-view persistence.
  Support/    Logging, notifications, preferences, and process cleanup helpers.
  Views/      SwiftUI app views.
script/       Local build and run helpers.
docs/         Architecture, privacy, and troubleshooting notes.
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Privacy](docs/PRIVACY.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Releasing](docs/RELEASING.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)
- [Support](SUPPORT.md)
- [Changelog](CHANGELOG.md)

## Releases

Push a `v*` tag to build and publish a GitHub release. Tags with `alpha`, `beta`, `rc`, `pre`, `preview`, or `wip` in the name are marked as prereleases. Every push to `main` also refreshes a rolling `wip-latest` prerelease with the newest app bundle.

## Contributing

Issues and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a PR, especially for changes involving credentials, ffmpeg process handling, local network discovery, or PTZ control.

## License

This project is available under the MIT License. See [LICENSE](LICENSE).
