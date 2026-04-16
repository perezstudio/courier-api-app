import Foundation
import SwiftData

@Observable
final class InspectorViewModel {
    var activeRun: APICallRun?
    var selectedTab: InspectorTab = .body
    var isCollapsed: Bool = false

    /// Bumped on every meaningful state change. Observers should watch this
    /// instead of reaching into SwiftData model properties directly.
    var version: UInt = 0

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
        self.version &+= 1
    }

    /// Call when the run's status or data changes externally (e.g., request completes).
    func runDidUpdate() {
        self.version &+= 1
    }

    func clear() {
        activeRun = nil
        self.version &+= 1
    }
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case body = "Body"
    case headers = "Headers"

    var id: String { rawValue }
}
