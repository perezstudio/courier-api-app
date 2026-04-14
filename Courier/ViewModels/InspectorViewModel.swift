import Foundation

@Observable
final class InspectorViewModel {
    var response: ResponseResult?
    var isLoading: Bool = false
    var error: String?
    var selectedTab: InspectorTab = .body
    var isCollapsed: Bool = false

    var hasResponse: Bool {
        response != nil
    }

    func setResponse(_ result: ResponseResult) {
        self.response = result
        self.error = nil
        self.isLoading = false
    }

    func setError(_ message: String) {
        self.error = message
        self.response = nil
        self.isLoading = false
    }

    func clear() {
        response = nil
        error = nil
        isLoading = false
    }
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case body = "Body"
    case headers = "Headers"

    var id: String { rawValue }
}
