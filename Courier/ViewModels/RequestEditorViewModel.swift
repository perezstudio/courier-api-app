import Foundation
import SwiftData

@Observable
final class RequestEditorViewModel {
    var currentRequest: APIRequest?

    var method: String = "GET"
    var urlString: String = ""
    var selectedTab: RequestEditorTab = .params

    // Params synced with URL
    var queryParams: [KeyValueRow] = []
    // Headers
    var headerRows: [KeyValueRow] = []
    // Body
    var bodyType: String? = "None"
    var bodyContent: String? = ""
    // Auth
    var authType: String? = "None"
    var authData: String? = ""

    private var modelContext: ModelContext
    private var isSyncingParams = false

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func loadRequest(_ request: APIRequest) {
        currentRequest = request
        method = request.method
        urlString = request.urlTemplate
        bodyType = request.bodyType ?? "None"
        bodyContent = request.bodyContent ?? ""
        authType = request.authType ?? "None"
        authData = request.authData ?? ""

        // Load query params
        queryParams = request.queryParams
            .sorted { $0.key < $1.key }
            .map { KeyValueRow(id: $0.id, key: $0.key, value: $0.value, isEnabled: $0.isEnabled) }

        // Load headers
        headerRows = request.headers
            .sorted { $0.key < $1.key }
            .map { KeyValueRow(id: $0.id, key: $0.key, value: $0.value, isEnabled: $0.isEnabled) }
    }

    func clearRequest() {
        currentRequest = nil
        method = "GET"
        urlString = ""
        selectedTab = .params
        queryParams = []
        headerRows = []
        bodyType = "None"
        bodyContent = ""
        authType = "None"
        authData = ""
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
        if !isSyncingParams {
            parseURLToParams()
        }
        try? modelContext.save()
    }

    func syncParamsToURL() {
        isSyncingParams = true
        defer { isSyncingParams = false }

        guard var components = URLComponents(string: baseURL) else { return }
        let enabledParams = queryParams.filter { $0.isEnabled && !$0.key.isEmpty }
        if enabledParams.isEmpty {
            components.queryItems = nil
        } else {
            components.queryItems = enabledParams.map {
                URLQueryItem(name: $0.key, value: $0.value)
            }
        }
        if let newURL = components.string {
            urlString = newURL
            currentRequest?.urlTemplate = newURL
            currentRequest?.updatedAt = Date()
            try? modelContext.save()
        }
    }

    func saveHeaders() {
        guard let request = currentRequest else { return }
        // Remove old headers
        for header in request.headers {
            modelContext.delete(header)
        }
        // Insert new
        for row in headerRows where !row.key.isEmpty {
            let header = Header(key: row.key, value: row.value, isEnabled: row.isEnabled)
            header.request = request
            modelContext.insert(header)
        }
        request.updatedAt = Date()
        try? modelContext.save()
    }

    func saveBody() {
        currentRequest?.bodyType = bodyType
        currentRequest?.bodyContent = bodyContent
        currentRequest?.updatedAt = Date()
        try? modelContext.save()
    }

    func saveAuth() {
        currentRequest?.authType = authType
        currentRequest?.authData = authData
        currentRequest?.updatedAt = Date()
        try? modelContext.save()
    }

    // MARK: - URL Parsing

    private var baseURL: String {
        guard let qIndex = urlString.firstIndex(of: "?") else { return urlString }
        return String(urlString[urlString.startIndex..<qIndex])
    }

    private func parseURLToParams() {
        guard let components = URLComponents(string: urlString) else { return }
        guard let items = components.queryItems, !items.isEmpty else {
            queryParams = []
            syncQueryParamsToModel()
            return
        }
        queryParams = items.map { item in
            KeyValueRow(key: item.name, value: item.value ?? "", isEnabled: true)
        }
        syncQueryParamsToModel()
    }

    private func syncQueryParamsToModel() {
        guard let request = currentRequest else { return }
        for param in request.queryParams {
            modelContext.delete(param)
        }
        for row in queryParams where !row.key.isEmpty {
            let param = QueryParam(key: row.key, value: row.value, isEnabled: row.isEnabled)
            param.request = request
            modelContext.insert(param)
        }
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
