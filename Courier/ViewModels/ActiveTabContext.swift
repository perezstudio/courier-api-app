import Foundation

/// Holds the ViewModel pair for a single open tab.
final class TabState {
    let editorVM: RequestEditorViewModel
    let inspectorVM: InspectorViewModel

    init(editorVM: RequestEditorViewModel, inspectorVM: InspectorViewModel) {
        self.editorVM = editorVM
        self.inspectorVM = inspectorVM
    }
}

/// Observable indirection layer for per-tab VM switching.
/// SwiftUI views and AppKit controllers observe this object.
/// When the active tab changes, `switchTo()` swaps the VM references,
/// triggering re-evaluation in all observers.
@Observable
final class ActiveTabContext {
    private(set) var editorVM: RequestEditorViewModel
    private(set) var inspectorVM: InspectorViewModel

    init(editorVM: RequestEditorViewModel, inspectorVM: InspectorViewModel) {
        self.editorVM = editorVM
        self.inspectorVM = inspectorVM
    }

    func switchTo(_ state: TabState) {
        self.editorVM = state.editorVM
        self.inspectorVM = state.inspectorVM
    }
}
