import Foundation
import SwiftData

@Model
final class APICallRunResponseHeaders {
    var id: UUID
    var run: APICallRun?

    /// JSON-encoded [String: String] of response headers
    var headersData: Data?

    var decoded: [String: String] {
        guard let data = headersData else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    init(run: APICallRun) {
        self.id = UUID()
        self.run = run
    }
}
