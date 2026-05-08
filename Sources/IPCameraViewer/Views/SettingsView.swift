import SwiftUI

@MainActor
struct SettingsView: View {
    @AppStorage(AppPreferenceKey.autoScanOnLaunch) private var autoScanOnLaunch = true
    @AppStorage(AppPreferenceKey.groupCamerasByLocation) private var groupCamerasByLocation = true
    @AppStorage(AppPreferenceKey.cameraSortOrder) private var sortOrderRawValue = CameraSortOrder.name.rawValue
    @AppStorage(AppPreferenceKey.showPreviewNameBadges) private var showPreviewNameBadges = true

    var body: some View {
        Form {
            Section("Library") {
                Toggle("Group cameras by location", isOn: $groupCamerasByLocation)

                Picker("Default sort", selection: $sortOrderRawValue) {
                    ForEach(CameraSortOrder.allCases) { order in
                        Text(order.label).tag(order.rawValue)
                    }
                }

                Toggle("Show preview name badges", isOn: $showPreviewNameBadges)
            }

            Section("Streams") {
                LabeledContent("HTTP/MJPEG") {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                LabeledContent("HLS .m3u8") {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                LabeledContent("Raw RTSP") {
                    Text("Bridge required")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Discovery") {
                Toggle("Scan on launch", isOn: $autoScanOnLaunch)

                LabeledContent("ONVIF") {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                LabeledContent("Bonjour / UPnP") {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                LabeledContent("Local Port Scan") {
                    Text("Bounded")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 460)
        .padding()
    }
}
