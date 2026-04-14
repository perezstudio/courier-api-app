import Foundation
import SwiftData

@Observable
final class RequestEditorViewModel {
    var currentRequest: APIRequest?

    var method: String = "GET"
    var urlString: String = ""
    var selectedTab: RequestEditorTab = .params

    private var modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func loadRequest(_ request: APIRequest) {
        currentRequest = request
        method = request.method
        urlString = request.urlTemplate
    }

    func clearRequest() {
        currentRequest = nil
        method = "GET"
        urlString = ""
        selectedTab = .params
    }

    func updateMethod(_ method: String) {
        self.method = method
        currentRequest?.method = method
        currentRequest?.updatedAt = Date()
        try? modelContext.save()
    }

    func updateURL(_ url: String) {
        self.urlString = url
        currentRequest?.urlTemplate = url
        currentRequest?.updatedAt = Date()
        try? modelContext.save()
    }
}

enum RequestEditorTab: String, CaseIterable, Identifiable {
    case params = "Params"
    case headers = "Headers"
    case body = "Body"
    case auth = "Auth"

    var id: String { rawValue }
}
