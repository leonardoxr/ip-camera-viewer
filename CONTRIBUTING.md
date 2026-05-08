# Contributing

Thanks for helping improve IP Camera Viewer.

This is a local-network macOS app that can touch camera credentials, local network discovery, ffmpeg processes, and media playback. Contributions should be careful, small enough to review, and clear about any privacy or security impact.

## Development Setup

Requirements:

- macOS 14 or newer.
- Swift 5.9 or newer.
- Xcode Command Line Tools.
- ffmpeg for RTSP playback and cast-view features.

Install dependencies:

```bash
xcode-select --install
brew install ffmpeg
```

Build:

```bash
swift build
```

Run:

```bash
./script/build_and_run.sh
```

Verify launch:

```bash
./script/build_and_run.sh --verify
```

## Pull Request Guidelines

- Keep each PR focused on one feature, bug fix, or refactor.
- Include a short description of the user-facing behavior.
- Mention any camera brands or protocols used for manual testing.
- Do not include real camera URLs, passwords, hostnames, screenshots with private spaces, packet captures, or local network addresses from your home or workplace.
- Prefer generic examples such as `192.168.1.20` in docs and tests.
- Update README or docs when behavior, setup, troubleshooting, security, or privacy expectations change.

## Code Style

- Follow the existing SwiftUI and Swift style in `Sources/IPCameraViewer`.
- Keep platform-specific AppKit interop isolated and documented when SwiftUI alone is not enough.
- Keep async network work off the main actor unless UI state must be updated.
- Use `OSLog` through the app loggers, and never log raw credentials or credential-bearing URLs.
- Prefer clear, concrete UI states over indefinite spinners.

## Security-Sensitive Areas

Please call out changes that touch:

- Keychain reads or writes.
- Camera password migration or persistence.
- RTSP URL construction.
- ffmpeg and ffprobe process arguments.
- PTZ authentication.
- Local network scanning or discovery.
- Temporary HLS output directories.

For these areas, include the manual test path you used and any remaining caveats.

## PR Checklist

- `swift build` passes.
- The app launches with `./script/build_and_run.sh --verify`.
- New or changed UI has been manually checked in a normal window size and a narrow window size.
- No real camera credentials, private IPs, or personal screenshots were added.
- Docs were updated if setup or behavior changed.
