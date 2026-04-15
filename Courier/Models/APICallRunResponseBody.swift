import Foundation
import SwiftData

@Model
final class APICallRunResponseBody {
    var id: UUID
    var run: APICallRun?

    /// Raw response bytes
    var rawBody: Data?
    /// Plain pretty-printed text (fallback display)
    var bodyString: String?
    /// Pre-highlighted NSAttributedString archived as Data
    var formattedBody: Data?

    init(run: APICallRun) {
        self.id = UUID()
        self.run = run
    }
}
