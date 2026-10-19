import SwiftUI
import Toasts
import VaultFeed
import VaultSettings

struct VaultMainNavigationView: View {
    @State var pasteboard: Pasteboard
    @State var localSettings: LocalSettings
    @State var deviceAuthenticationService: DeviceAuthenticationService
    @State var vaultDataModel: VaultDataModel
    @State var injector: VaultInjector
    @Binding var pendingOpenItemDetail: Identifier<VaultItem>?
    @Environment(\.presentToast) private var presentToast

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.crease) private var crease
    /// Where the split view is in the window, to meet a crease.
    @State private var frame: CGRect?
    @State private var isShowingCopyPaste = false
    @State private var selectedView: SidebarItem?

    enum SidebarItem: Hashable {
        case items
        case tags
        case backups
        case settings
        case about
        case demos
    }

    init(
        pasteboard: Pasteboard,
        localSettings: LocalSettings,
        deviceAuthenticationService: DeviceAuthenticationService,
        vaultDataModel: VaultDataModel,
        injector: VaultInjector,
        pendingOpenItemDetail: Binding<Identifier<VaultItem>?> = .constant(nil),
        initialSelection: SidebarItem? = .items,
    ) {
        _pasteboard = State(initialValue: pasteboard)
        _localSettings = State(initialValue: localSettings)
        _deviceAuthenticationService = State(initialValue: deviceAuthenticationService)
        _vaultDataModel = State(initialValue: vaultDataModel)
        _injector = State(initialValue: injector)
        _pendingOpenItemDetail = pendingOpenItemDetail
        _selectedView = State(initialValue: initialSelection)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedView) {
                Section {
                    NavigationLink(value: SidebarItem.items) {
                        Label("Items", systemImage: "key.horizontal.fill")
                    }
                    .accessibilityIdentifier("sidebar.items")
                    NavigationLink(value: SidebarItem.tags) {
                        Label("Tags", systemImage: "tag.fill")
                    }
                }

                Section {
                    NavigationLink(value: SidebarItem.backups) {
                        Label("Backups", systemImage: "externaldrive.fill")
                    }
                }

                Section {
                    NavigationLink(value: SidebarItem.settings) {
                        Label("Settings", systemImage: "gear")
                    }
                    .accessibilityIdentifier("sidebar.settings")

                    NavigationLink(value: SidebarItem.about) {
                        Label("About", systemImage: "info.bubble.fill")
                    }

                    #if DEBUG
                    // Debug-only, and kept out of marketing screenshots.
                    if !ScreenshotMode.isEnabled {
                        NavigationLink(value: SidebarItem.demos) {
                            Label("Developer", systemImage: "hammer.fill")
                        }
                        .tint(.purple)
                    }
                    #endif
                }
            }
            .navigationTitle("Vault")
            .listStyle(.sidebar)
            .modifier(SidebarMeetsTheCrease(width: sidebarWidthToMeetTheCrease))
        } detail: {
            // Show the selected view in the detail area
            switch selectedView {
            case .items:
                VaultListView(
                    localSettings: localSettings,
                    viewGenerator: VaultRoot.genericVaultItemPreviewViewGenerator,
                    copyActionHandler: VaultRoot.vaultItemCopyHandler,
                    previewActionHandler: VaultRoot.vaultItemPreviewActionHandler,
                    pendingOpenItemDetail: $pendingOpenItemDetail,
                )
                .navigationBarTitleDisplayMode(.inline)
            case .tags:
                NavigationStack {
                    VaultTagFeedView(viewModel: .init())
                }
                .keepsToOnePageOfTheCrease()
            case .settings:
                NavigationStack {
                    VaultSettingsView(viewModel: SettingsViewModel(), localSettings: localSettings)
                }
                .navigationBarTitleDisplayMode(.inline)
                .keepsToOnePageOfTheCrease()
            case .about:
                NavigationStack {
                    VaultAboutView(viewModel: SettingsViewModel())
                }
                .navigationBarTitleDisplayMode(.inline)
                .keepsToOnePageOfTheCrease()
            case .backups:
                NavigationStack {
                    BackupHomeView()
                }
                .navigationBarTitleDisplayMode(.inline)
                .keepsToOnePageOfTheCrease()
            case .demos:
                NavigationStack {
                    DeveloperToolsHomeView()
                }
                .navigationBarTitleDisplayMode(.inline)
            case .none:
                Text("Select an option from the sidebar")
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationTitle("")
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .onReceive(pasteboard.didPaste()) {
            let toast = ToastValue(
                icon: Image(systemName: "doc.on.doc.fill"),
                message: localized(key: "code.copyied"),
            )
            presentToast(toast)
        }
        .task {
            await vaultDataModel.setup()
        }
        .environment(pasteboard)
        .environment(deviceAuthenticationService)
        .environment(vaultDataModel)
        .environment(injector)
        .environment(\.newItemDefaults, localSettings.state.newItemDefaults)
        .onChange(of: pendingOpenItemDetail) { _, newValue in
            if newValue != nil {
                selectedView = .items
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            switch newValue {
            case .background:
                vaultDataModel.purgeSensitiveData()
            case .active, .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}

extension VaultMainNavigationView {
    /// With a vertical crease through the split view, the sidebar is as wide as the leading page, so the sidebar and
    /// the content beside it meet at the crease, and neither has anything across it. Where the content fills the
    /// window, with the sidebar hidden or the window too narrow for both, it keeps out of the crease itself.
    private var sidebarWidthToMeetTheCrease: Double? {
        guard let crease, crease.axis == .vertical, let frame, let split = crease.split(frame) else { return nil }
        return split.before + Crease.bandWidth / 2
    }
}

private struct SidebarMeetsTheCrease: ViewModifier {
    var width: Double?

    func body(content: Content) -> some View {
        if let width {
            content
                .navigationSplitViewColumnWidth(width)
        } else {
            content
        }
    }
}
