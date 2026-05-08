# Releasing

This project has GitHub Actions workflows for CI, tagged releases, and rolling WIP prereleases.

## Workflows

- `CI` builds the Swift package and app bundle on pull requests and pushes to `main`.
- `Release` publishes a GitHub release when a tag matching `v*` is pushed.
- `WIP Prerelease` replaces the rolling `wip-latest` prerelease on each push to `main`.

Tags containing `alpha`, `beta`, `rc`, `pre`, `preview`, or `wip` are marked as prereleases automatically.

## Create A Release

Create and push a tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Create a prerelease:

```bash
git tag v0.1.0-beta.1
git push origin v0.1.0-beta.1
```

The workflow builds `dist/IPCameraViewer.app`, archives it as `IPCameraViewer-macOS.zip`, creates a SHA-256 checksum, and attaches both files to the GitHub release.

## Manual Release

The `Release` workflow can also be run manually from GitHub Actions with a tag name and prerelease flag.

## Checklist

1. Confirm `swift build` passes.
2. Confirm `./script/build_and_run.sh --verify` launches the app.
3. Manually test:
   - Add camera.
   - Discover cameras.
   - HLS playback.
   - RTSP bridge playback with ffmpeg.
   - Saved view rendering.
   - Cast view.
   - PTZ on a supported camera.
4. Review `README.md`, `CHANGELOG.md`, and `SECURITY.md`.
5. Confirm no private camera data is present:

```bash
rg -n "192\\.168\\.31|rtsp://[^\\s\\\"]+@|password\\s*[:=]" .
```

6. Create a version tag.
7. Push a `v*` tag or run the `Release` workflow manually.
8. If distributing production binaries outside GitHub source releases, sign and notarize the app.

## Current Distribution Status

The repository is ready for source distribution and unsigned/ad-hoc GitHub release bundles. Production binary distribution still needs a signing, hardened runtime, notarization, and update-channel decision.
