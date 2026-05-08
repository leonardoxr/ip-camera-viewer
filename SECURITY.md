# Security Policy

## Supported Versions

Security fixes are accepted for the current `main` branch. If release tags are added later, this section should be updated with the supported release range.

## Reporting A Vulnerability

Please do not open a public issue for a vulnerability involving credentials, camera access, local network exposure, or command execution.

Use a private GitHub security advisory if available. If advisories are not enabled, contact the maintainer through a private channel listed on the maintainer profile.

Include:

- A short description of the issue.
- The affected feature or file path.
- Reproduction steps using placeholder addresses such as `192.168.1.20`.
- Whether credentials, camera streams, local files, or local process state are exposed.
- Any logs with secrets removed.

Do not include real camera passwords, full credential-bearing RTSP URLs, packet captures, or screenshots of private spaces.

## Security Model

IP Camera Viewer is a local desktop app. It is intended to connect to cameras and NVRs on networks the user controls.

The app currently:

- Stores camera passwords in the macOS Keychain.
- Stores camera and saved-view metadata in user Application Support JSON files with owner-only permissions.
- Uses ffmpeg for local RTSP-to-HLS bridging and composite view casting.
- Creates temporary HLS files in the user's temporary directory.
- Sends local network discovery probes for ONVIF, Bonjour, SSDP/UPnP, and common camera ports.

## Known Caveat

RTSP bridging currently launches ffmpeg with the input stream URL in the process arguments. If that URL contains embedded credentials, another local process owned by the same user may be able to observe them through process inspection while the bridge is running.

Preferred mitigations for users:

- Use dedicated low-privilege camera accounts.
- Avoid sharing process listings or crash reports from active streams.
- Keep camera passwords unique.

Preferred future mitigation for contributors:

- Move credential handoff away from process arguments where ffmpeg support and camera compatibility allow it.
