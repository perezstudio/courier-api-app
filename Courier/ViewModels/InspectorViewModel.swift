import Foundation
import SwiftData

@Observable
final class InspectorViewModel {
    var activeRun: APICallRun?
    var selectedTab: InspectorTab = .body
    var isCollapsed: Bool = false

    var isLoading: Bool {
        guard let run = activeRun else { return false }
        return run.status == .pending || run.status == .running
    }

    var hasResponse: Bool {
        activeRun?.status == .completed
    }

    var hasError: Bool {
        activeRun?.status == .failed
    }

    var errorMessage: String? {
        activeRun?.errorMessage
    }

    func setActiveRun(_ run: APICallRun) {
        self.activeRun = run
        self.isCollapsed = false
    }

    func clear() {
        activeRun = nil
    }
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case body = "Body"
    case headers = "Headers"

    var id: String { rawValue }
}
