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
    let runService: RunService

    // Per-tab VM storage
    private var tabStates: [UUID: TabState] = [:]
    let activeTabContext: ActiveTabContext

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let context = ModelContext(modelContainer)
        self.sharedContext = context
        self.sidebarVM = SidebarViewModel(modelContext: context)
        self.runService = RunService(modelContainer: modelContainer)

        // Create initial placeholder VMs for ActiveTabContext
        let initialEditorVM = RequestEditorViewModel(modelContext: context)
        let initialInspectorVM = InspectorViewModel()
        self.activeTabContext = ActiveTabContext(
            editorVM: initialEditorVM,
            inspectorVM: initialInspectorVM
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        object_setClass(splitView, InvisibleDividerSplitView.self)
        splitView.dividerStyle = .thin
        splitView.isVertical = true

        setupViewControllers()
        observeActiveEditorMethod()
    }

    /// Observes the active tab's editor VM method so the tab badge stays in sync
    /// when the user changes the method via the picker. Re-establishes itself on each fire.
    private func observeActiveEditorMethod() {
        withObservationTracking {
            // Track the active editor VM identity AND its method
            _ = activeTabContext.editorVM.method
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                if let tabId = self.tabBarVM.activeTabId {
                    self.tabBarVM.updateMethod(self.activeTabContext.editorVM.method, forTab: tabId)
                }
                self.observeActiveEditorMethod()
            }
        }
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
            activeTabContext: activeTabContext,
            onCloseTab: { [weak self] tabId in
                guard let self else { return }
                // Remove the tab's VM state
                self.tabStates.removeValue(forKey: tabId)
                self.tabBarVM.closeTab(tabId)
                if let nextTab = self.tabBarVM.activeTab {
                    self.switchToTab(nextTab)
                } else {
                    // No tabs left — clear context
                    self.activeTabContext.editorVM.clearRequest()
                    self.activeTabContext.inspectorVM.clear()
                }
            },
            onSelectTab: { [weak self] tab in
                self?.switchToTab(tab)
            },
            onNewTab: { [weak self] in
                self?.createNewUnsavedTab()
            },
            onSend: { [weak self] in
                self?.sendCurrentRequest()
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

        guard let tabId = tabBarVM.activeTabId else { return }

        if let existing = tabStates[tabId] {
            // Tab already has VMs — just switch to it
            activeTabContext.switchTo(existing)
        } else {
            // New tab — create VM pair, load request once
            let editorVM = RequestEditorViewModel(modelContext: sharedContext)
            let inspectorVM = InspectorViewModel()
            let state = TabState(editorVM: editorVM, inspectorVM: inspectorVM)
            tabStates[tabId] = state

            editorVM.loadRequest(request)
            activeTabContext.switchTo(state)

            // Restore last run in background
            restoreRunForTab(tabId: tabId, request: request, inspectorVM: inspectorVM)
        }
    }

    private func switchToTab(_ tab: RequestTab) {
        guard let state = tabStates[tab.id] else { return }
        activeTabContext.switchTo(state)
    }

    private func restoreRunForTab(tabId: UUID, request: APIRequest, inspectorVM: InspectorViewModel) {
        let trackedRunId = tabBarVM.activeRunId(forTab: tabId)
        let requestId = request.id
        let container = modelContainer

        Task.detached(priority: .userInitiated) {
            let bgContext = ModelContext(container)

            let run: APICallRun?
            if let runId = trackedRunId {
                let descriptor = FetchDescriptor<APICallRun>(
                    predicate: #Predicate { $0.id == runId }
                )
                run = try? bgContext.fetch(descriptor).first
            } else {
                let descriptor = FetchDescriptor<APICallRun>(
                    predicate: #Predicate { $0.request?.id == requestId },
                    sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
                )
                run = try? bgContext.fetch(descriptor).first
            }

            let foundRunId = run?.id

            await MainActor.run { [weak self] in
                guard let self else { return }
                if let foundRunId {
                    let mainDescriptor = FetchDescriptor<APICallRun>(
                        predicate: #Predicate { $0.id == foundRunId }
                    )
                    if let mainRun = try? self.sharedContext.fetch(mainDescriptor).first {
                        inspectorVM.setActiveRun(mainRun)
                        if trackedRunId == nil {
                            self.tabBarVM.setActiveRun(mainRun.id, forTab: tabId)
                        }
                    } else {
                        inspectorVM.clear()
                    }
                } else {
                    inspectorVM.clear()
                }
            }
        }
    }

    private func sendCurrentRequest() {
        let editorVM = activeTabContext.editorVM
        let inspectorVM = activeTabContext.inspectorVM

        guard let request = editorVM.currentRequest else { return }

        let url = editorVM.urlString
        let method = editorVM.method
        let headers = editorVM.headerRows
            .filter { $0.isEnabled && !$0.key.isEmpty }
            .map { (key: $0.key, value: $0.value) }
        let bodyType = editorVM.bodyType
        let bodyContent = editorVM.bodyContent

        guard !url.isEmpty else { return }

        // Capture inspectorVM by value — updates go to this tab's inspector
        // even if user switches away before request completes
        let run = runService.executeRun(
            for: request,
            method: method,
            urlString: url,
            headers: headers,
            bodyType: bodyType,
            bodyContent: bodyContent,
            context: sharedContext,
            onStatusChange: { inspectorVM.runDidUpdate() }
        )

        inspectorVM.setActiveRun(run)

        if let tabId = tabBarVM.activeTabId {
            tabBarVM.setActiveRun(run.id, forTab: tabId)
        }
    }

    private func createNewUnsavedTab() {
        // Create a new request in the first workspace's first folder (or create one)
        guard let workspace = sidebarVM.currentWorkspace else { return }
        let folder: Folder
        if let first = workspace.folders.first {
            folder = first
        } else {
            let newFolder = Folder(name: "Requests", sortOrder: 0)
            newFolder.workspace = workspace
            sharedContext.insert(newFolder)
            try? sharedContext.save()
            sidebarVM.fetchWorkspaces()
            folder = newFolder
        }
        let request = APIRequest(name: "New Request", method: "GET", sortOrder: folder.requests.count)
        request.folder = folder
        sharedContext.insert(request)
        try? sharedContext.save()
        sidebarVM.fetchWorkspaces()
        handleRequestSelection(request)
    }

    func toggleSidebar() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            sidebarItem.animator().isCollapsed.toggle()
        }
    }
}
