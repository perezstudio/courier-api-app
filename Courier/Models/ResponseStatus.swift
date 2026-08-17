import AppKit

/// What the toolbar's status chip shows: just the code, tinted by its class.
///
/// Deliberately only the code. Duration and size were a second line under it,
/// which made the toolbar heavy for information that is already listed per run
/// in the History tab.
nonisolated struct ResponseStatus: Equatable {
    var title: String
    var color: NSColor

    static func from(_ result: ExecutionResult) -> ResponseStatus {
        ResponseStatus(
            title: "\(result.statusCode)",
            color: Theme.color(forStatusCode: result.statusCode)
        )
    }

    static func from(_ summary: RunSummary) -> ResponseStatus {
        guard let code = summary.statusCode else {
            return ResponseStatus(title: "Failed", color: .systemRed)
        }
        return ResponseStatus(title: "\(code)", color: Theme.color(forStatusCode: code))
    }

    static let failure = ResponseStatus(title: "Failed", color: .systemRed)
}
