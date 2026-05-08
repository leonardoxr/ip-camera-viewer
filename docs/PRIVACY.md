# Privacy

IP Camera Viewer is local-first. It does not upload video, camera metadata, passwords, or discovery results to a cloud service.

## Data Stored On Disk

Camera metadata:

```text
~/Library/Application Support/IPCameraViewer/cameras.json
```

Saved view metadata:

```text
~/Library/Application Support/IPCameraViewer/camera-views.json
```

Temporary HLS bridge data:

```text
$TMPDIR/IPCameraViewer/
```

The app tries to clean bridge directories on launch and termination.

## Password Storage

Camera passwords are stored in the macOS Keychain using the service:

```text
IPCameraViewer.CameraCredentials
```

Camera JSON should not contain passwords after a successful save or migration. If Keychain access is denied, the app may be unable to persist or retrieve that camera password.

If you accidentally deny Keychain access, open the macOS Keychain Access app and inspect the relevant `IPCameraViewer.CameraCredentials` entry permissions, or edit the camera and save the password again.

## Network Activity

The app may send local network traffic for:

- ONVIF WS-Discovery.
- Bonjour/mDNS lookup.
- SSDP/UPnP lookup.
- Known camera host probing.
- Common camera HTTP/HTTPS/RTSP port checks.
- Camera stream playback.
- PTZ commands.

Discovery and playback are intended for networks you own or are authorized to use.

## Logs

Runtime logs are written through Apple's unified logging system. Logs should use redacted URLs when credentials are involved.

Before sharing logs, check for:

- Camera usernames.
- Camera passwords.
- Full RTSP URLs.
- Private hostnames.
- Private IP addresses.
- Screenshots of private spaces.

## ffmpeg Process Arguments

RTSP and composite cast features use local ffmpeg processes. ffmpeg currently receives input stream URLs as process arguments. If an input URL includes credentials, those credentials can be visible to local process inspection while the bridge is running.

Use dedicated camera accounts with limited permissions where possible.
