import AppKit
import SwiftData
import SwiftUI

final class MainSplitViewController: NSSplitViewController {
    private let modelContainer: ModelContainer
    private let sharedContext: ModelContext
    private var sidebarItem: NSSplitViewItem!
    private var mainAreaItem: NSSplitViewItem!

    let sidebarVM: SidebarViewModel
    let tabBarVM = TabBarViewModel()
    let requestEditorVM: RequestEditorViewModel
    let inspectorVM = InspectorViewModel()

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let context = ModelContext(modelContainer)
        self.sharedContext = context
        self.sidebarVM = SidebarViewModel(modelContext: context)
        self.requestEditorVM = RequestEditorViewModel(modelContext: context)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        splitView.dividerStyle = .thin
        splitView.isVertical = true

        setupViewControllers()
    }

    private func setupViewControllers() {
        // Sidebar
        let sidebarView = SidebarView(
            viewModel: sidebarVM,
            onSelectRequest: { [weak self] request in
                self?.handleRequestSelection(request)
            }
        )
        let sidebarHC = NSHostingController(rootView: sidebarView)
        if #available(macOS 13.0, *) {
            sidebarHC.sizingOptions = []
        }

        sidebarItem = NSSplitViewItem(viewController: sidebarHC)
        sidebarItem.canCollapse = true
        sidebarItem.minimumThickness = 220
        sidebarItem.maximumThickness = 320
        sidebarItem.holdingPriority = .defaultLow + 1
        addSplitViewItem(sidebarItem)

        // Main Area (tab bar + content card)
        let mainAreaView = MainAreaView(
            tabBarVM: tabBarVM,
            requestEditorVM: requestEditorVM,
            inspectorVM: inspectorVM,
            onCloseTab: { [weak self] tabId in
                self?.tabBarVM.closeTab(tabId)
                if self?.tabBarVM.activeTab == nil {
                    self?.requestEditorVM.clearRequest()
                }
            },
            onSelectTab: { [weak self] tab in
                self?.loadRequestForTab(tab)
            }
        )
        let mainAreaHC = NSHostingController(rootView: mainAreaView)
        if #available(macOS 13.0, *) {
            mainAreaHC.sizingOptions = []
        }

        mainAreaItem = NSSplitViewItem(viewController: mainAreaHC)
        mainAreaItem.minimumThickness = 500
        mainAreaItem.holdingPriority = .defaultLow
        addSplitViewItem(mainAreaItem)
    }

    private func handleRequestSelection(_ request: APIRequest) {
        tabBarVM.openRequest(request)
        requestEditorVM.loadRequest(request)
        inspectorVM.clear()
    }

    private func loadRequestForTab(_ tab: RequestTab) {
        let targetId = tab.requestId
        let descriptor = FetchDescriptor<APIRequest>(
            predicate: #Predicate { $0.id == targetId }
        )
        if let request = try? sharedContext.fetch(descriptor).first {
            requestEditorVM.loadRequest(request)
            inspectorVM.clear()
        }
    }

    func toggleSidebar() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            sidebarItem.animator().isCollapsed.toggle()
        }
    }
}
