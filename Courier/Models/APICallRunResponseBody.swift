import Foundation
import SwiftData

@Model
final class APICallRunResponseBody {
    var id: UUID
    var run: APICallRun?

    /// Raw response bytes
    var rawBody: Data?
    /// Plain pretty-printed text
    var bodyString: String?

    init(run: APICallRun) {
        self.id = UUID()
        self.run = run
    }
}
