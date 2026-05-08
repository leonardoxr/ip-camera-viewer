# Troubleshooting

## Cameras Are Not Found

Being on 5 GHz while a camera is on 2.4 GHz should not matter when both bands are bridged into the same LAN.

Check:

- The Mac and cameras are not on separate guest, IoT, or VLAN networks.
- Client isolation is disabled.
- Multicast, Bonjour/mDNS, SSDP, or ONVIF discovery is not blocked by the router.
- The camera has local discovery enabled in its admin settings.
- The camera is powered on and connected.
- The Discover sheet direct IP probe works with a known address such as `192.168.1.20`.

## Camera Adds But Video Does Not Play

Discovery often finds the device endpoint, not the final stream URL.

Check:

- Username and password.
- RTSP path after host and port.
- Whether the camera requires a main stream or substream path.
- Whether the selected quality preset maps to the right stream subtype.
- Whether ffmpeg is installed.

For many Dahua and Intelbras-style cameras, a typical RTSP path looks like:

```text
rtsp://192.168.1.20:554/cam/realmonitor?channel=1&subtype=0
```

Use `subtype=1` for a lighter substream when supported.

## Install ffmpeg

```bash
brew install ffmpeg
```

Then restart the app.

## Keychain Keeps Asking For Permission

Choose "Always Allow" in the macOS Keychain prompt when you trust the app build.

If you denied access by mistake:

1. Open Keychain Access.
2. Search for `IPCameraViewer.CameraCredentials`.
3. Remove stale denied entries or adjust access control.
4. Reopen the app.
5. Edit the camera and save its password again.

Local development builds can trigger new prompts when the app bundle identity changes.

## RTSP Bridge Spins Or Fails

Check:

- ffmpeg is installed.
- The RTSP URL is reachable from the Mac.
- The password is saved and available from Keychain.
- The RTSP stream path is correct.
- The camera account has permission to view RTSP.
- Try the Stable quality preset for lower bandwidth and CPU usage.
- Try Compatibility encoder mode if VideoToolbox fails on the machine.

## PTZ Does Not Move

PTZ support depends on camera model, firmware, API route, and account permissions.

Check:

- The camera account has PTZ permission.
- The app has a saved username and password.
- The camera is using a supported PTZ API path.
- Vendor apps may use a cloud or private API that differs from the local camera API.

If opening an issue, include the camera brand, model, firmware version, and the redacted PTZ error message.

## View Cast Does Not Work

View casting needs ffmpeg and at least one playable camera in the saved view.

Check:

- ffmpeg is installed.
- Each camera plays individually.
- The saved view uses an appropriate quality preset.
- Low CPU mode works on the Mac; otherwise try Compatibility mode.
- AirPlay is available from the AVPlayer controls after the composite stream starts.
