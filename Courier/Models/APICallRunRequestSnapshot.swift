import Foundation
import SwiftData

@Model
final class APICallRunRequestSnapshot {
    var id: UUID
    var run: APICallRun?

    /// JSON-encoded headers that were sent
    var requestHeaders: Data?
    /// Body content that was sent
    var requestBody: String?
    /// Body type (JSON, XML, etc.)
    var requestBodyType: String?

    init(run: APICallRun) {
        self.id = UUID()
        self.run = run
    }
}
