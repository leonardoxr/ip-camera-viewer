import SwiftUI

struct ContentView: View {
    @Environment(CameraStore.self) private var store
    @Environment(DiscoveryStore.self) private var discoveryStore
    @SceneStorage(AppPreferenceKey.selectedSidebarItem) private var storedSelection = SidebarSelection.overview.storageValue
    @SceneStorage(AppPreferenceKey.librarySearchText) private var searchText = ""
    @AppStorage(AppPreferenceKey.autoScanOnLaunch) private var autoScanOnLaunch = true
    @AppStorage(AppPreferenceKey.groupCamerasByLocation) private var isGroupedByLocation = true
    @State private var isShowingAddCamera = false
    @State private var isShowingAddCameraView = false
    @State private var isShowingDiscovery = false
    @State private var editingCamera: Camera?
    @State private var editingCameraView: CameraViewLayout?

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: selectionBinding,
                onAddCamera: { isShowingAddCamera = true },
                onDiscoverCameras: { isShowingDiscovery = true },
                onEditCamera: { editingCamera = $0 },
                onDeleteCamera: deleteCamera,
                onAddCameraView: { isShowingAddCameraView = true },
                onEditCameraView: { editingCameraView = $0 },
                onDeleteCameraView: deleteCameraView
            )
        } detail: {
            detailView
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    if isViewingCameraViews {
                        isShowingAddCameraView = true
                    } else {
                        isShowingAddCamera = true
                    }
                } label: {
                    Label(isViewingCameraViews ? "New View" : "Add Camera", systemImage: "plus")
                }
                .help(isViewingCameraViews ? "New View" : "Add Camera")

                Button {
                    isShowingDiscovery = true
                } label: {
                    Label("Discover Cameras", systemImage: "network")
                }
                .help("Discover ONVIF Cameras")
            }
        }
        .searchable(text: $searchText, prompt: "Search Cameras")
        .sheet(isPresented: $isShowingAddCamera) {
            CameraFormView(camera: nil) { camera in
                store.add(camera)
                select(.camera(camera.id))
            }
        }
        .sheet(item: $editingCamera) { camera in
            CameraFormView(camera: camera) { updatedCamera in
                store.update(updatedCamera)
                select(.camera(updatedCamera.id))
            }
        }
        .sheet(isPresented: $isShowingAddCameraView) {
            CameraViewFormView(cameraView: nil, cameras: store.cameras) { cameraView in
                store.add(cameraView)
                select(.cameraView(cameraView.id))
            }
        }
        .sheet(item: $editingCameraView) { cameraView in
            CameraViewFormView(cameraView: cameraView, cameras: store.cameras) { updatedCameraView in
                store.update(updatedCameraView)
                select(.cameraView(updatedCameraView.id))
            }
        }
        .sheet(isPresented: $isShowingDiscovery) {
            DiscoveryView()
        }
        .task {
            if autoScanOnLaunch {
                discoveryStore.scanIfNeeded()
            } else {
                AppLoggers.discovery.debug("Automatic launch discovery skipped by user preference")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAddCameraSheet)) { _ in
            AppLoggers.commands.info("Opening add camera sheet")
            isShowingAddCamera = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showDiscoverySheet)) { _ in
            AppLoggers.commands.info("Opening discovery sheet")
            isShowingDiscovery = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .scanCameras)) { _ in
            discoveryStore.scan()
            isShowingDiscovery = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearCameraSearch)) { _ in
            AppLoggers.commands.info("Clearing camera search")
            searchText = ""
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleCameraGrouping)) { _ in
            isGroupedByLocation.toggle()
            let groupingState = isGroupedByLocation ? "enabled" : "disabled"
            AppLoggers.commands.info("Camera grouping is now \(groupingState, privacy: .public)")
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch currentSelection {
        case .overview:
            CameraGridView(
                cameras: store.cameras,
                searchText: $searchText,
                isGroupedByLocation: $isGroupedByLocation
            ) { camera in
                select(.camera(camera.id))
            }
        case .views:
            CameraViewsManagerView(
                cameraViews: store.cameraViews,
                cameras: store.cameras,
                onCreate: { isShowingAddCameraView = true },
                onOpen: { select(.cameraView($0.id)) },
                onEdit: { editingCameraView = $0 },
                onDelete: deleteCameraView
            )
        case .cameraView(let id):
            if let cameraView = store.cameraView(id: id) {
                CameraViewDashboardView(
                    cameraView: cameraView,
                    cameras: store.cameras(in: cameraView),
                    onSelectCamera: { select(.camera($0.id)) },
                    onEdit: { editingCameraView = cameraView },
                    onDelete: { deleteCameraView(cameraView) }
                )
            } else {
                CameraViewsManagerView(
                    cameraViews: store.cameraViews,
                    cameras: store.cameras,
                    onCreate: { isShowingAddCameraView = true },
                    onOpen: { select(.cameraView($0.id)) },
                    onEdit: { editingCameraView = $0 },
                    onDelete: deleteCameraView
                )
            }
        case .camera(let id):
            if let camera = store.camera(id: id) {
                CameraDetailView(
                    camera: camera,
                    onEdit: { editingCamera = camera },
                    onDelete: { deleteCamera(camera) }
                )
            } else {
                CameraGridView(
                    cameras: store.cameras,
                    searchText: $searchText,
                    isGroupedByLocation: $isGroupedByLocation
                ) { camera in
                    select(.camera(camera.id))
                }
            }
        }
    }

    private func deleteCamera(_ camera: Camera) {
        store.delete(camera)
        if case .camera(let selectedID) = currentSelection, selectedID == camera.id {
            select(.overview)
        }
    }

    private func deleteCameraView(_ cameraView: CameraViewLayout) {
        store.delete(cameraView)
        if case .cameraView(let selectedID) = currentSelection, selectedID == cameraView.id {
            select(.views)
        }
    }

    private var currentSelection: SidebarSelection {
        SidebarSelection(storageValue: storedSelection) ?? .overview
    }

    private var isViewingCameraViews: Bool {
        switch currentSelection {
        case .views, .cameraView:
            true
        case .overview, .camera:
            false
        }
    }

    private var selectionBinding: Binding<SidebarSelection> {
        Binding {
            currentSelection
        } set: { newSelection in
            select(newSelection)
        }
    }

    private func select(_ newSelection: SidebarSelection) {
        storedSelection = newSelection.storageValue
        AppLoggers.sidebar.info("Selected \(newSelection.logLabel, privacy: .public)")
    }
}
