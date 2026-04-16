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
    let runService: RunService

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let context = ModelContext(modelContainer)
        self.sharedContext = context
        self.sidebarVM = SidebarViewModel(modelContext: context)
        self.requestEditorVM = RequestEditorViewModel(modelContext: context)
        self.runService = RunService(modelContainer: modelContainer)
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
                guard let self else { return }
                self.tabBarVM.closeTab(tabId)
                if let nextTab = self.tabBarVM.activeTab {
                    // Switch to the next tab's content
                    self.loadRequestForTab(nextTab)
                } else {
                    // No tabs left — clear everything
                    self.requestEditorVM.clearRequest()
                    self.inspectorVM.clear()
                }
            },
            onSelectTab: { [weak self] tab in
                self?.loadRequestForTab(tab)
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
        requestEditorVM.loadRequest(request)
        // Restore run in background so tab switch is instant
        restoreRunForActiveTabAsync(request: request)
    }

    private func loadRequestForTab(_ tab: RequestTab) {
        let targetId = tab.requestId
        let descriptor = FetchDescriptor<APIRequest>(
            predicate: #Predicate { $0.id == targetId }
        )
        if let request = try? sharedContext.fetch(descriptor).first {
            requestEditorVM.loadRequest(request)
            restoreRunForActiveTabAsync(request: request)
        }
    }

    private func restoreRunForActiveTabAsync(request: APIRequest) {
        let tabId = tabBarVM.activeTabId
        let trackedRunId = tabId.flatMap { tabBarVM.activeRunId(forTab: $0) }
        let requestId = request.id
        let container = modelContainer

        Task.detached(priority: .userInitiated) {
            let bgContext = ModelContext(container)

            let run: APICallRun?
            if let runId = trackedRunId {
                // Fetch the tracked run
                let descriptor = FetchDescriptor<APICallRun>(
                    predicate: #Predicate { $0.id == runId }
                )
                run = try? bgContext.fetch(descriptor).first
            } else {
                // No run tracked — find the most recent
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
                    // Re-fetch on main context so we have a main-thread object
                    let mainDescriptor = FetchDescriptor<APICallRun>(
                        predicate: #Predicate { $0.id == foundRunId }
                    )
                    if let mainRun = try? self.sharedContext.fetch(mainDescriptor).first {
                        self.inspectorVM.setActiveRun(mainRun)
                        if let tabId, trackedRunId == nil {
                            self.tabBarVM.setActiveRun(mainRun.id, forTab: tabId)
                        }
                    } else {
                        self.inspectorVM.clear()
                    }
                } else {
                    self.inspectorVM.clear()
                }
            }
        }
    }

    private func sendCurrentRequest() {
        guard let request = requestEditorVM.currentRequest else { return }

        let url = requestEditorVM.urlString
        let method = requestEditorVM.method
        let headers = requestEditorVM.headerRows
            .filter { $0.isEnabled && !$0.key.isEmpty }
            .map { (key: $0.key, value: $0.value) }
        let bodyType = requestEditorVM.bodyType
        let bodyContent = requestEditorVM.bodyContent

        guard !url.isEmpty else { return }

        let run = runService.executeRun(
            for: request,
            method: method,
            urlString: url,
            headers: headers,
            bodyType: bodyType,
            bodyContent: bodyContent,
            context: sharedContext,
            onStatusChange: { [weak self] in
                self?.inspectorVM.runDidUpdate()
            }
        )

        inspectorVM.setActiveRun(run)

        // Track this run on the active tab
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
